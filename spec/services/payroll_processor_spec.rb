require "rails_helper"

RSpec.describe "SlipBuilder + PayrollRunProcessor" do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:month) { Date.new(2027, 6, 1) } # June 2027: 30 days, 8 weekend days (sat_sun), 22 working

  describe HrLite::SlipBuilder do
    it "composes a full-attendance month end to end" do
      profile = create(:employee_profile)
      structure = create(:salary_structure, user: profile.user,
                         basic: 40000, hra: 20000, special_allowance: 15000)
      run = create(:payroll_run, period_month: month)
      # No punches at all -> whole working month is LOP; use overrides to
      # simulate full attendance instead (deterministic, no 22 punch rows).
      attrs = described_class.call(run: run, user: profile.user, structure: structure,
                                   profile: profile, lop_override: BigDecimal("0"))

      expect(attrs[:payable_days]).to eq(30)
      earnings = JSON.parse(attrs[:earnings])
      expect(earnings.find { |r| r["code"] == "basic" }["amount"]).to eq("40000.0")
      expect(attrs[:gross_earnings]).to eq(75000)

      deductions = JSON.parse(attrs[:deductions])
      codes = deductions.to_h { |r| [ r["code"], BigDecimal(r["amount"]) ] }
      expect(codes["pf_employee"]).to eq(1800)      # capped wage
      expect(codes).not_to have_key("esi_employee") # gross 75k > 21k ceiling
      expect(attrs[:net_pay]).to eq(attrs[:gross_earnings] - attrs[:total_deductions])
    end

    it "yields zero TDS under the rebate cap" do
      profile = create(:employee_profile)
      structure = create(:salary_structure, user: profile.user, basic: 40000, hra: 20000,
                                            special_allowance: 15000)
      run = create(:payroll_run, period_month: month)
      attrs = described_class.call(run: run, user: profile.user, structure: structure,
                                   profile: profile, lop_override: BigDecimal("0"))
      deductions = JSON.parse(attrs[:deductions]).map { |r| r["code"] }
      expect(deductions).not_to include("tds") # 9L annual gross is far below the 12L rebate cap
    end

    it "applies LOP proration and window clipping" do
      profile = create(:employee_profile, date_of_joining: Date.new(2027, 6, 16)) # joins mid-month
      structure = create(:salary_structure, user: profile.user, basic: 30000, hra: nil,
                                            special_allowance: nil)
      run = create(:payroll_run, period_month: month)
      travel_to(Date.new(2027, 7, 5)) do
        attrs = described_class.call(run: run, user: profile.user, structure: structure,
                                     profile: profile)
        # 15 days out of window (1-15 June); working days 16-30 June unpunched -> LOP
        summary = HrLite::AttendanceSummary.for(user: profile.user, month: month)
        expect(summary[:out_of_window]).to eq(15)
        expect(attrs[:payable_days]).to eq(30 - 15 - attrs[:lop_days])
      end
    end
  end

  describe HrLite::PayrollRunProcessor do
    it "creates slips for eligible employees, warns on missing structures, prunes ineligible" do
      with_structure = create(:employee_profile)
      create(:salary_structure, user: with_structure.user)
      without_structure = create(:employee_profile)
      exited = create(:employee_profile, date_of_joining: Date.new(2024, 1, 1),
                                         date_of_exit: Date.new(2027, 1, 31))
      create(:salary_structure, user: exited.user)

      run = create(:payroll_run, period_month: month)
      run.compute!(actor: leader)

      expect(run.salary_slips.map(&:user_id)).to eq([ with_structure.user_id ])
      expect(run.warnings.join).to include("No salary structure")

      # Employee becomes ineligible before recompute -> slip pruned.
      with_structure.update!(date_of_exit: Date.new(2027, 5, 31))
      run.compute!(actor: leader)
      expect(run.salary_slips.reload).to be_empty
    end

    it "preserves overrides across recomputes" do
      profile = create(:employee_profile)
      create(:salary_structure, user: profile.user)
      run = create(:payroll_run, period_month: month)
      run.compute!(actor: leader)

      slip = run.salary_slips.first
      slip.update!(lop_override: BigDecimal("2"), tds_override: BigDecimal("500"))

      run.compute!(actor: leader)
      slip.reload
      expect(slip.lop_override).to eq(2)
      expect(slip.tds_override).to eq(500)
      expect(slip.payable_days).to eq(28) # 30 - 0 oow - 2 lop override
      expect(slip.deduction_amount("tds")).to eq(500)
    end
  end
end
