require "rails_helper"

RSpec.describe "Payroll models" do
  describe HrLite::EmployeeProfile do
    it "validates identity formats when present" do
      expect(build(:employee_profile, pan_number: "ABCDE1234F")).to be_valid
      expect(build(:employee_profile, pan_number: "bad")).not_to be_valid
      expect(build(:employee_profile, bank_ifsc: "HDFC0001234")).to be_valid
      expect(build(:employee_profile, bank_ifsc: "XX99")).not_to be_valid
      expect(build(:employee_profile, pf_uan: "123456789012")).to be_valid
      expect(build(:employee_profile, pf_uan: "123")).not_to be_valid
      expect(build(:employee_profile, tax_regime: "flat")).not_to be_valid
      expect(build(:employee_profile, date_of_exit: Date.new(2023, 1, 1))).not_to be_valid
    end

    it "encrypts PII at rest" do
      profile = create(:employee_profile, pan_number: "ABCDE1234F", bank_account_number: "1234567890")
      raw = profile.class.connection.select_value(
        "SELECT pan_number FROM hr_lite_employee_profiles WHERE id = #{profile.id}"
      )
      expect(raw).not_to include("ABCDE1234F")
      expect(profile.reload.pan_number).to eq("ABCDE1234F")
    end

    it "masks PAN, UAN and account" do
      profile = build(:employee_profile, pan_number: "ABCDE1234F", pf_uan: "123456789012",
                                         bank_account_number: "000111222333")
      expect(profile.masked_pan).to eq("AB••••••4F")
      expect(profile.masked_uan).to eq("12••••••••12")
      expect(profile.masked_account).to eq("•••• 2333")
      expect(build(:employee_profile).masked_pan).to be_nil
    end

    it "computes the employment window" do
      profile = build(:employee_profile, date_of_joining: Date.new(2027, 6, 10),
                                         date_of_exit: Date.new(2027, 7, 20))
      expect(profile.active_on?(Date.new(2027, 6, 9))).to be(false)
      expect(profile.active_on?(Date.new(2027, 7, 1))).to be(true)
      expect(profile.active_on?(Date.new(2027, 7, 21))).to be(false)
      expect(profile.employment_range_in(Date.new(2027, 6, 1)))
        .to eq(Date.new(2027, 6, 10)..Date.new(2027, 6, 30))
      expect(profile.employment_range_in(Date.new(2027, 8, 1))).to be_nil
    end

    it "scopes active_for a month across joins and exits" do
      current = create(:employee_profile, date_of_joining: Date.new(2027, 6, 15))
      exited = create(:employee_profile, date_of_joining: Date.new(2024, 1, 1),
                                         date_of_exit: Date.new(2027, 5, 31))
      future = create(:employee_profile, date_of_joining: Date.new(2027, 8, 1))

      active = described_class.active_for(Date.new(2027, 6, 1))
      expect(active).to include(current)
      expect(active).not_to include(exited, future)
    end
  end

  describe HrLite::SalaryStructure do
    it "requires positive basic and first-of-month effectivity" do
      expect(build(:salary_structure, basic: 0)).not_to be_valid
      expect(build(:salary_structure, effective_from: Date.new(2026, 1, 15))).not_to be_valid
      expect(build(:salary_structure)).to be_valid
    end

    it "round-trips encrypted money as BigDecimal" do
      structure = create(:salary_structure, basic: "40000.555")
      expect(structure.reload.basic).to eq(BigDecimal("40000.56"))
      expect(structure.basic).to be_a(BigDecimal)
      structure.update!(hra: nil)
      expect(structure.reload.hra).to be_nil
    end

    it "derives gross and picks the effective version" do
      user = create(:user)
      old = create(:salary_structure, user: user, effective_from: Date.new(2026, 1, 1), basic: 30000, hra: nil, special_allowance: nil)
      new_one = create(:salary_structure, user: user, effective_from: Date.new(2027, 4, 1), basic: 40000, hra: 10000, special_allowance: nil)

      expect(new_one.monthly_gross).to eq(50000)
      expect(new_one.annual_gross).to eq(600000)
      expect(described_class.effective_for(user, Date.new(2027, 3, 1))).to eq(old)
      expect(described_class.effective_for(user, Date.new(2027, 4, 1))).to eq(new_one)
      expect(described_class.effective_for(user, Date.new(2025, 1, 1))).to be_nil
    end
  end

  describe HrLite::PayrollRun do
    let(:leader) { create(:user, email: "lead@x.test") }

    it "validates first-of-month uniqueness" do
      create(:payroll_run, period_month: Date.new(2027, 6, 1))
      expect(build(:payroll_run, period_month: Date.new(2027, 6, 1))).not_to be_valid
      expect(build(:payroll_run, period_month: Date.new(2027, 6, 2))).not_to be_valid
    end

    it "walks the lifecycle and blocks illegal transitions" do
      run = create(:payroll_run)
      create(:employee_profile, user: create(:user), date_of_joining: Date.new(2024, 1, 1)).tap do |p|
        create(:salary_structure, user: p.user)
      end

      expect { run.finalize!(actor: leader) }.to raise_error(ActiveRecord::RecordInvalid)
      run.compute!(actor: leader)
      expect(run.reload).to be_review
      run.finalize!(actor: leader)
      expect(run.reload).to be_finalized
      run.unlock!(actor: leader)
      expect(run.reload).to be_review
      run.finalize!(actor: leader)
      run.publish!(actor: leader)
      expect(run.reload).to be_published
      expect { run.publish!(actor: leader) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses to finalize an empty run" do
      run = create(:payroll_run)
      run.compute!(actor: leader) # no eligible employees -> zero slips
      expect { run.finalize!(actor: leader) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "reverts to draft when compute blows up" do
      run = create(:payroll_run)
      allow(HrLite::PayrollRunProcessor).to receive(:call).and_raise("boom")
      expect { run.compute!(actor: leader) }.to raise_error("boom")
      expect(run.reload).to be_draft
    end

    it "only draft runs can be destroyed" do
      run = create(:payroll_run, status: "review")
      expect(run.destroy).to be(false)
      run.update_columns(status: "draft") # rubocop:disable Rails/SkipsModelValidations
      expect(run.destroy).to be_truthy
    end

    it "publishes notifications to every slip owner" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      HrLite.config.leadership_emails = [ "lead@x.test" ]

      run = create(:payroll_run)
      profile = create(:employee_profile)
      create(:salary_structure, user: profile.user)
      run.compute!(actor: leader)
      run.finalize!(actor: leader)
      run.publish!(actor: leader)

      kinds = bells.map { |b| b[:kind] }
      expect(kinds).to include("payroll.published")
      expect(bells.find { |b| b[:kind] == "payroll.published" }[:user]).to eq(profile.user)
    end
  end

  describe HrLite::SalarySlip do
    let(:leader) { create(:user, email: "lead@x.test") }

    def computed_run(month: Date.new(2027, 6, 1))
      run = create(:payroll_run, period_month: month)
      profile = create(:employee_profile)
      create(:salary_structure, user: profile.user)
      run.compute!(actor: leader)
      run
    end

    it "serializes encrypted JSON line items round-trip" do
      run = computed_run
      slip = run.salary_slips.first
      expect(slip.earnings_rows.map { |r| r["code"] }).to include("basic")
      expect(slip.deductions_rows.map { |r| r["code"] }).to include("pf_employee")
      expect(slip.employer_costs_hash).to include("pf_eps")
      raw = slip.class.connection.select_value("SELECT earnings FROM hr_lite_salary_slips WHERE id = #{slip.id}")
      expect(raw).not_to include("basic")
    end

    it "is immutable once the run is finalized" do
      run = computed_run
      run.finalize!(actor: leader)
      slip = run.salary_slips.first
      expect { slip.update!(payable_days: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "is visible to employees only when published" do
      run = computed_run
      expect(HrLite::SalarySlip.published).to be_empty
      run.finalize!(actor: leader)
      run.publish!(actor: leader)
      expect(HrLite::SalarySlip.published.count).to eq(1)
    end

    it "sums FY-to-date over published slips with the April boundary" do
      user = create(:user)
      create(:employee_profile, user: user)
      # 1.5L/month => 18L projected annual, well above the rebate cap, so TDS flows.
      create(:salary_structure, user: user, basic: 150000, hra: nil, special_allowance: nil)

      [ Date.new(2027, 3, 1), Date.new(2027, 4, 1), Date.new(2027, 5, 1) ].each do |month|
        run = create(:payroll_run, period_month: month)
        run.compute!(actor: leader)
        run.finalize!(actor: leader)
        run.publish!(actor: leader)
      end

      fy = HrLite::SalarySlip.fy_to_date(user, Date.new(2027, 6, 1))
      expect(fy[:months]).to eq(2) # March belongs to FY 2026-27
      expect(fy[:gross]).to eq(300000)
      expect(fy[:tds]).to be > 0
    end
  end
end
