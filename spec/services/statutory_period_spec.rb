require "rails_helper"

RSpec.describe "Statutory periods and opening balances" do
  let(:user) { create(:user, name: "Meera") }
  let!(:profile) { create(:employee_profile, user: user, date_of_joining: Date.new(2024, 1, 1)) }

  describe "ESI eligibility within a contribution period" do
    # ESIC periods run Apr–Sep and Oct–Mar. Eligibility is fixed for the whole
    # period, so a raise past the ceiling mid-period must not end coverage —
    # it used to, because eligibility was re-decided from the current salary
    # every single month.
    it "keeps someone covered after a mid-period raise past the ceiling" do
      create(:salary_structure, user: user, effective_from: Date.new(2026, 4, 1),
             basic: 18000, hra: nil, special_allowance: nil, esi_applicable: true)
      raised = create(:salary_structure, user: user, effective_from: Date.new(2026, 7, 1),
                      basic: 40000, hra: nil, special_allowance: nil, esi_applicable: true)
      run = HrLite::PayrollRun.new(period_month: Date.new(2026, 8, 1))

      builder = HrLite::SlipBuilder.new(run, user, raised, profile, nil, nil)

      # August sits in the April–September period, which opened at ₹18,000.
      expect(builder.send(:esi_reference_gross)).to eq(BigDecimal("18000"))
    end

    it "re-reads the salary at the next period boundary" do
      create(:salary_structure, user: user, effective_from: Date.new(2026, 4, 1),
             basic: 18000, hra: nil, special_allowance: nil, esi_applicable: true)
      raised = create(:salary_structure, user: user, effective_from: Date.new(2026, 7, 1),
                      basic: 40000, hra: nil, special_allowance: nil, esi_applicable: true)
      run = HrLite::PayrollRun.new(period_month: Date.new(2026, 11, 1))

      builder = HrLite::SlipBuilder.new(run, user, raised, profile, nil, nil)

      # November sits in October–March, which opened at the raised salary.
      expect(builder.send(:esi_reference_gross)).to eq(BigDecimal("40000"))
    end

    it "falls back to the current salary for someone who joined mid-period" do
      structure = create(:salary_structure, user: user, effective_from: Date.new(2026, 8, 1),
                         basic: 25000, hra: nil, special_allowance: nil)
      run = HrLite::PayrollRun.new(period_month: Date.new(2026, 8, 1))

      builder = HrLite::SlipBuilder.new(run, user, structure, profile, nil, nil)

      expect(builder.send(:esi_reference_gross)).to eq(BigDecimal("25000"))
    end
  end

  describe "income this FY that this install never ran" do
    # A run is only valid for a month that has ended.
    around { |example| travel_to(Date.new(2026, 11, 5)) { example.run } }

    # Only slips from THIS install feed the projection, so starting payroll in
    # October read April–September as zero income — often landing the whole
    # year under the rebate cap and deducting nothing.
    it "counts the opening balance in the projection" do
      profile.update!(fy_opening_gross: 900_000, fy_opening_tds: 40_000)
      structure = create(:salary_structure, user: user, effective_from: Date.new(2026, 10, 1),
                         basic: 150_000, hra: nil, special_allowance: nil)
      run = create(:payroll_run, period_month: Date.new(2026, 10, 1))

      attrs = HrLite::SlipBuilder.call(run: run, user: user, structure: structure, profile: profile)
      details = JSON.parse(attrs[:tax_details])

      expect(BigDecimal(details["projected_annual_gross"])).to be > BigDecimal("900000")
      expect(details["fy_tds_already_deducted"]).to eq("40000.0")
    end

    it "treats a blank opening balance as zero" do
      structure = create(:salary_structure, user: user, effective_from: Date.new(2026, 10, 1),
                         basic: 150_000, hra: nil, special_allowance: nil)
      run = create(:payroll_run, period_month: Date.new(2026, 10, 1))

      expect {
        HrLite::SlipBuilder.call(run: run, user: user, structure: structure, profile: profile)
      }.not_to raise_error
    end
  end
end
