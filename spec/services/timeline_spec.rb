require "rails_helper"

RSpec.describe HrLite::Timeline, no_legacy_bridge: true do
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:colleague) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Dev") }
  let(:superadmin) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Asha") }
  let(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Farah") }

  before do
    travel_to(Date.new(2027, 7, 15))
    HrLite::SalaryComponent.seed_defaults!
    create(:employee_profile, user: meera, date_of_joining: Date.new(2027, 1, 4), date_of_exit: Date.new(2027, 7, 1))
    HrLite::DesignationChange.create!(user: meera, to_designation: "Senior Executive", effective_date: Date.new(2027, 4, 1))
    HrLite::DesignationChange.create!(user: meera, to_designation: "Lead", effective_date: Date.new(2027, 9, 1)) # not yet
    kudo = create(:kudo, giver: colleague, badge: "team_player", message: "Thanks @[Meera](#{meera.id})")
    kudo.register_mentions!
    HrLite::Award.create!(user: meera, kind: "month", period_start: Date.new(2027, 5, 9), citation: "Rebooked 12 pax")
    create(:leave_request, :approved, user: meera, start_date: Date.new(2027, 6, 1), end_date: Date.new(2027, 6, 2))
    HrLite::PayrollLineItem.create!(user_id: meera.id, period_month: Date.new(2027, 3, 1), amount: 5_000,
                                    component: HrLite::SalaryComponent.find_by!(code: "bonus"))
    HrLite::Loan.create!(user_id: meera.id, principal: 30_000, monthly_instalment: 10_000, starts_on: Date.new(2027, 2, 1), reason: "Rent")
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    HrLite::Expense.create!(user_id: meera.id, category: category, amount: 900, spent_on: Date.new(2027, 2, 10), description: "Cab")
                   .update_columns(status: "reimbursed") # rubocop:disable Rails/SkipsModelValidations
    create(:appraisal, user: meera, reviewer: superadmin).update_columns(status: "shared", shared_at: Time.zone.local(2027, 3, 20)) # rubocop:disable Rails/SkipsModelValidations
    HrLite::PerformancePlan.create!(user: meera, start_date: Date.new(2027, 5, 1), end_date: Date.new(2027, 6, 1), goals: "Close 10 files")
                           .update!(status: "passed", outcome_note: "Met every goal")
  end

  after { travel_back }

  def titles(viewer) = described_class.new(user: meera, viewer: viewer, year: 2027).events.map(&:title)

  it "shows a colleague only the public story, with leave but not its type" do
    expect(titles(colleague)).to eq([
      "Kudos from Dev", "Left the company", "On leave", "Employee of the month — May 2027", "New role: Senior Executive", "Joined"
    ])
  end

  it "shows the employee and Super Admin everything, private rows marked" do
    [ meera, superadmin ].each do |viewer|
      events = described_class.new(user: meera, viewer: viewer, year: 2027).events
      expect(events.map(&:title)).to include(HrLite::LeaveRequest.sole.leave_type.name, "Bonus", "Loan of ₹30,000.00",
                                             "Expense reimbursed: Travel", "Appraisal #{HrLite::Appraisal.sole.period_label}",
                                             "Performance improvement plan started",
                                             "Performance improvement plan passed")
      expect(events.select(&:sensitive).size).to eq(6)
    end
  end

  it "shows Finance the money rows but never the appraisal or the PIP" do
    expect(titles(finance)).to include("Bonus", "Loan of ₹30,000.00", "Expense reimbursed: Travel")
    expect(titles(finance).grep(/Appraisal|Performance/)).to be_empty
  end

  it "keeps other years out" do
    expect(described_class.new(user: meera, viewer: meera, year: 2026).events).to be_empty
  end
end
