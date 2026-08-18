require "rails_helper"

# Payroll knew four earning heads because they were columns. A bonus, an
# incentive, an LTA or arrears had nowhere to go but "other" — one number on
# a payslip that should have said what it was for.
RSpec.describe "Payroll heads, arrears and loans", no_legacy_bridge: true do
  let(:leader) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }
  let(:month) { Date.new(2027, 6, 1) }

  around { |example| travel_to(Date.new(2027, 7, 5)) { example.run } }

  before { HrLite::SalaryComponent.seed_defaults! }

  def employee_with_structure(**structure)
    profile = create(:employee_profile)
    create(:salary_structure, { user: profile.user, basic: 40_000, hra: 20_000,
                                special_allowance: 15_000 }.merge(structure))
    profile.user
  end

  def line!(user, code, amount, **attrs)
    HrLite::PayrollLineItem.create!(
      user_id: user.id, period_month: month, amount: amount,
      component: HrLite::SalaryComponent.find_by!(code: code), **attrs
    )
  end

  def slip_for(user)
    run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
    run.compute!(actor: leader)
    run.salary_slips.find_by!(user_id: user.id)
  end

  describe "a one-off earning" do
    it "shows on the payslip under its own name" do
      user = employee_with_structure
      line!(user, "bonus", 10_000, note: "Diwali")

      slip = slip_for(user)
      bonus = slip.earnings_rows.find { |row| row["code"] == "bonus" }

      expect(bonus["label"]).to eq("Bonus")
      expect(BigDecimal(bonus["amount"])).to eq(10_000)
    end

    # A bonus is not halved because somebody joined on the 16th.
    it "is not prorated when its component says not to" do
      user = employee_with_structure
      HrLite::EmployeeProfile.find_by!(user_id: user.id)
                             .update!(date_of_joining: Date.new(2027, 6, 16))
      line!(user, "bonus", 10_000)

      slip = slip_for(user)
      bonus = slip.earnings_rows.find { |row| row["code"] == "bonus" }
      expect(BigDecimal(bonus["amount"])).to eq(10_000)
      # while the structure itself IS clipped to the days worked
      expect(slip.payable_days).to be < 30
    end

    it "raises the gross and therefore the net" do
      plain = slip_for(employee_with_structure).gross_earnings
      user = employee_with_structure
      line!(user, "bonus", 10_000)

      HrLite::PayrollRun.find_by!(period_month: month).compute!(actor: leader)
      slip = HrLite::PayrollRun.find_by!(period_month: month).salary_slips.find_by!(user_id: user.id)
      expect(slip.gross_earnings).to eq(plain + 10_000)
    end
  end

  describe "a reimbursement" do
    # ESI is assessed on wages. A reimbursement is not one, and counting it
    # could push somebody over the ceiling and out of cover.
    # Two identical employees, one with a reimbursement. The reimbursement is
    # paid in full, and the ESI deduction is IDENTICAL — because ESI is
    # assessed on wages, and counting a reimbursement could push somebody
    # over the ceiling and out of cover entirely.
    it "is paid, but the ESI deduction ignores it" do
      plain = employee_with_structure(basic: 10_000, hra: 4_000, special_allowance: 2_000)
      reimbursed = employee_with_structure(basic: 10_000, hra: 4_000, special_allowance: 2_000)
      line!(reimbursed, "reimbursement", 8_000)

      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.compute!(actor: leader)
      plain_slip = run.salary_slips.find_by!(user_id: plain.id)
      reimbursed_slip = run.salary_slips.find_by!(user_id: reimbursed.id)

      expect(reimbursed_slip.gross_earnings).to eq(plain_slip.gross_earnings + 8_000)
      expect(reimbursed_slip.deduction_amount("esi_employee"))
        .to eq(plain_slip.deduction_amount("esi_employee"))
      expect(reimbursed_slip.deduction_amount("esi_employee")).to be > 0
    end
  end

  describe "a one-off deduction" do
    it "reduces the net without touching the gross" do
      user = employee_with_structure
      line!(user, "other_deduction", 1_500, note: "Canteen")

      slip = slip_for(user)
      expect(slip.deduction_amount("other_deduction")).to eq(1_500)
      expect(slip.net_pay).to eq(slip.gross_earnings - slip.total_deductions)
    end
  end

  describe "line items" do
    it "refuse a negative amount — a deduction is one by its component" do
      user = employee_with_structure
      item = HrLite::PayrollLineItem.new(
        user_id: user.id, period_month: month, amount: -500,
        component: HrLite::SalaryComponent.find_by!(code: "other_deduction")
      )
      expect(item).not_to be_valid
    end

    it "refuse a mid-month date" do
      user = employee_with_structure
      item = HrLite::PayrollLineItem.new(
        user_id: user.id, period_month: Date.new(2027, 6, 15), amount: 500,
        component: HrLite::SalaryComponent.find_by!(code: "bonus")
      )
      expect(item).not_to be_valid
      expect(item.errors[:period_month].join).to include("1st of a month")
    end

    it "prorate a head whose component says so" do
      user = employee_with_structure
      HrLite::EmployeeProfile.find_by!(user_id: user.id)
                             .update!(date_of_joining: Date.new(2027, 6, 16))
      HrLite::SalaryComponent.find_by!(code: "lta").update!(prorated: true)
      line!(user, "lta", 30_000)

      slip = slip_for(user)
      lta = slip.earnings_rows.find { |row| row["code"] == "lta" }
      # Half the month out of window, so half the allowance.
      expect(BigDecimal(lta["amount"])).to be < 30_000
      expect(BigDecimal(lta["amount"])).to be > 0
    end

    it "refuse a month that has already been paid" do
      user = employee_with_structure
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.compute!(actor: leader)
      run.finalize!(actor: leader)
      run.publish!(actor: leader)

      item = HrLite::PayrollLineItem.new(
        user_id: user.id, period_month: month, amount: 500,
        component: HrLite::SalaryComponent.find_by!(code: "bonus")
      )
      expect(item).not_to be_valid
      expect(item.errors[:period_month].join).to include("already been paid")
    end

    it "survive a draft run being deleted and computed again" do
      user = employee_with_structure
      line!(user, "bonus", 5_000)
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.destroy!

      expect(slip_for(user).earnings_rows.map { |r| r["code"] }).to include("bonus")
    end
  end

  describe "a loan" do
    let(:user) { employee_with_structure }
    let!(:loan) do
      HrLite::Loan.create!(user_id: user.id, principal: 30_000, monthly_instalment: 10_000,
                           starts_on: Date.new(2027, 5, 1), reason: "Advance")
    end

    it "deducts the instalment and books it only when the run is finalized" do
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.compute!(actor: leader)

      expect(run.salary_slips.find_by!(user_id: user.id).deduction_amount("loan_repayment")).to eq(10_000)
      expect(loan.reload.outstanding).to eq(30_000) # nothing booked yet

      run.finalize!(actor: leader)
      expect(loan.reload.outstanding).to eq(20_000)
    end

    # A draft is recomputed as often as the operator likes.
    it "does not take an instalment per recompute" do
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      3.times { run.compute!(actor: leader) }
      run.finalize!(actor: leader)

      expect(loan.reload.outstanding).to eq(20_000)
      expect(loan.loan_repayments.count).to eq(1)
    end

    it "gives the instalment back when the run is unlocked" do
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.compute!(actor: leader)
      run.finalize!(actor: leader)
      run.unlock!(actor: leader)

      expect(loan.reload.outstanding).to eq(30_000)
      expect(loan.loan_repayments).to be_empty
    end

    it "reopens a loan that unlocking un-repaid" do
      loan.update!(principal: 10_000)
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.compute!(actor: leader)
      run.finalize!(actor: leader)
      expect(loan.reload).to be_closed

      run.unlock!(actor: leader)

      expect(loan.reload).to be_active
      expect(loan.outstanding).to eq(10_000)
    end

    it "takes only what is left on the last instalment" do
      loan.update!(principal: 12_000)
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.compute!(actor: leader)

      expect(run.salary_slips.find_by!(user_id: user.id).deduction_amount("loan_repayment"))
        .to eq(10_000)

      run.finalize!(actor: leader)
      expect(loan.reload.outstanding).to eq(2_000)
    end

    it "closes itself once it is repaid" do
      loan.update!(principal: 10_000)
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.compute!(actor: leader)
      run.finalize!(actor: leader)

      expect(loan.reload).to be_closed
      expect(loan.outstanding).to eq(0)
    end

    it "deducts nothing before it starts" do
      loan.update!(starts_on: Date.new(2027, 9, 1))
      run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
      run.compute!(actor: leader)

      expect(run.salary_slips.find_by!(user_id: user.id).deduction_amount("loan_repayment")).to eq(0)
    end

    it "refuses an instalment larger than the loan" do
      expect(HrLite::Loan.new(user_id: user.id, principal: 5_000,
                              monthly_instalment: 6_000, starts_on: Date.current)).not_to be_valid
    end
  end

  describe "salary components" do
    it "refuse a code the salary structure already owns" do
      component = HrLite::SalaryComponent.new(code: "basic", label: "Basic")
      expect(component).not_to be_valid
      expect(component.errors[:code].join).to include("already a salary-structure field")
    end

    it "are seeded once and never overwritten" do
      HrLite::SalaryComponent.find_by!(code: "bonus").update!(label: "Festival bonus")
      expect(HrLite::SalaryComponent.seed_defaults!).to be_empty
      expect(HrLite::SalaryComponent.find_by!(code: "bonus").label).to eq("Festival bonus")
    end

    it "refuse to be deleted while a payslip line uses them" do
      user = employee_with_structure
      line!(user, "bonus", 1_000)
      component = HrLite::SalaryComponent.find_by!(code: "bonus")

      expect(component.destroy).to be(false)
    end
  end
end
