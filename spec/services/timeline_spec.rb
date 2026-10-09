require "rails_helper"

RSpec.describe HrLite::Timeline, no_legacy_bridge: true do
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:colleague) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Dev") }
  let(:superadmin) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Asha") }
  let(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Farah") }

  def at(month, day = 10) = Time.zone.local(2027, month, day, 12)

  before do
    travel_to(Date.new(2027, 7, 15))
    HrLite::SalaryComponent.seed_defaults!
    create(:employee_profile, user: meera, date_of_joining: Date.new(2027, 1, 4), date_of_exit: Date.new(2027, 7, 1),
                              probation_until: Date.new(2027, 6, 30))
    HrLite::DesignationChange.create!(user: meera, to_designation: "Senior Executive", effective_date: Date.new(2027, 4, 1))
    HrLite::DesignationChange.create!(user: meera, to_designation: "Lead", effective_date: Date.new(2027, 9, 1)) # not yet
    create(:kudo, giver: colleague, badge: "team_player", message: "Thanks @[Meera](#{meera.id})").register_mentions!
    create(:kudo, giver: meera, message: "Great save @[Dev](#{colleague.id})").register_mentions!
    HrLite::Award.create!(user: meera, kind: "month", period_start: Date.new(2027, 5, 9), citation: "Rebooked 12 pax")
    create(:leave_request, :approved, user: meera, start_date: Date.new(2027, 6, 1), end_date: Date.new(2027, 6, 1))
    HrLite::PayrollLineItem.create!(user_id: meera.id, period_month: Date.new(2027, 3, 1), amount: 5_000,
                                    component: HrLite::SalaryComponent.find_by!(code: "bonus"))
    HrLite::Loan.create!(user_id: meera.id, principal: 30_000, monthly_instalment: 10_000, starts_on: Date.new(2027, 2, 1), reason: "Rent")
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    HrLite::Expense.create!(user_id: meera.id, category: category, amount: 900, spent_on: Date.new(2027, 2, 10), description: "Cab")
                   .update_columns(status: "reimbursed") # rubocop:disable Rails/SkipsModelValidations
    create(:appraisal, user: meera, reviewer: superadmin).update_columns(status: "shared", shared_at: at(3, 20)) # rubocop:disable Rails/SkipsModelValidations
    HrLite::PerformancePlan.create!(user: meera, start_date: Date.new(2027, 5, 1), end_date: Date.new(2027, 6, 1), goals: "Close 10 files")
                           .update!(status: "passed", outcome_note: "Met every goal")
    create(:regularization_request, user: meera, date: Date.new(2027, 6, 7)).update_columns(status: "approved") # rubocop:disable Rails/SkipsModelValidations
    create(:comp_off_request, user: meera, date_worked: Date.new(2027, 5, 15)).update_columns(status: "approved") # rubocop:disable Rails/SkipsModelValidations
    laptop = HrLite::Asset.create!(name: "ThinkPad", category: "laptop", serial_number: "SN1")
    HrLite::AssetAssignment.create!(asset: laptop, user: meera, assigned_on: Date.new(2027, 1, 5), returned_on: Date.new(2027, 7, 1))
    HrLite::Document.create!(user: meera, category: "pan", title: "PAN card", visibility: "hr", verification: "verified", verified_at: at(1, 6))
    HrLite::Resignation.new(user: meera, reason: "Moving", proposed_last_day: Date.new(2027, 7, 1), status: "accepted",
                            decided_at: at(6, 5), created_at: at(6, 1)).save!(validate: false) # filed before its last day
    HrLite::HrRequest.create!(user: meera, category: HrLite::HrRequest::CATEGORIES.first, subject: "Salary letter", body: "Please",
                              status: "resolved", resolved_at: at(4, 2), resolution: "Sent")
  end

  after { travel_back }

  def timeline(viewer, year: 2027) = described_class.new(user: meera, viewer: viewer, year: year)

  it "gives a colleague the public story only, with leave but not its type, and no private rows" do
    expect(timeline(colleague).public_events.map(&:title)).to eq([
      "Kudos from Dev", "Gave kudos to Dev", "Left the company", "On leave",
      "Employee of the month — May 2027", "New role: Senior Executive", "Joined the company"
    ])
    expect(timeline(colleague).private_events).to be_empty
  end

  it "gives the employee and Super Admin every private record" do
    [ meera, superadmin ].each do |viewer|
      expect(timeline(viewer).public_events.map(&:title)).to include(HrLite::LeaveRequest.sole.leave_type.name)
      expect(timeline(viewer).private_events.map(&:category).uniq).to match_array(
        %w[Pay Expense Performance Attendance Leave Asset Document Exit Milestone] + [ "Help desk" ]
      )
      expect(timeline(viewer).private_events.map(&:title)).to include(
        "Loan of ₹30,000.00", "Performance improvement plan passed", "Returned ThinkPad", "Resignation accepted",
        "Probation ended", "Request resolved: Salary letter", "Document verified: PAN card"
      )
    end
  end

  it "gives Finance the money rows but never the appraisal, the PIP or the HR-only document" do
    titles = timeline(finance).private_events.map(&:title)
    expect(titles).to include("Bonus", "Loan of ₹30,000.00", "Expense reimbursed: Travel")
    expect(titles.grep(/Appraisal|Performance|Document/)).to be_empty
  end

  it "keeps other years out" do
    expect(timeline(meera, year: 2026).public_events + timeline(meera, year: 2026).private_events).to be_empty
  end
end
