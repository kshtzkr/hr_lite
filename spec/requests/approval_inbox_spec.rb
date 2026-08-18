require "rails_helper"

RSpec.describe "The approval inbox", type: :request, no_legacy_bridge: true do
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let!(:other_manager) { user_with_roles(HrLite::Role::MANAGER, name: "Bilal") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:leave_type) { create(:leave_type, code: "CL", name: "Casual", annual_quota: 12) }

  # Thursday 17 June 2027. Leave lands on the Monday and Tuesday after —
  # `Date.current + 9` is a weekend on most days of the week, and leave that
  # covers no working day is refused at creation.
  around { |example| travel_to(Date.new(2027, 6, 17)) { example.run } }

  before do
    create(:employee_profile, user: employee, manager_id: manager.id)
    flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Leave")
    flow.approval_steps.create!(position: 1, approver_rule: "manager", sla_hours: 24)
  end

  def leave!
    create(:leave_request, user: employee, leave_type: leave_type,
                           start_date: Date.new(2027, 6, 21), end_date: Date.new(2027, 6, 21))
  end

  it "lists what is waiting on this person and nothing else" do
    leave!
    sign_in manager
    get "/hr/approvals"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Meera", "Leave request")

    sign_in other_manager
    get "/hr/approvals"
    expect(response.body).to include("Nothing is waiting on you")
  end

  it "is reachable by an employee — holding an approval is the authorisation" do
    sign_in employee
    get "/hr/approvals"
    expect(response).to have_http_status(:ok)
  end

  it "shows a stand-in the rows they are covering, marked as somebody else's" do
    leave!
    stand_in = user_with_roles(HrLite::Role::EMPLOYEE, name: "Priya")
    HrLite::ApprovalDelegation.create!(from_user: manager, to_user: stand_in,
                                        starts_on: Date.current, ends_on: Date.current + 5)

    sign_in stand_in
    get "/hr/approvals"

    expect(response.body).to include("You are covering for", "Asha", "for Asha")
  end

  it "tells the approver who is covering while they are away" do
    stand_in = user_with_roles(HrLite::Role::EMPLOYEE, name: "Priya")
    HrLite::ApprovalDelegation.create!(from_user: manager, to_user: stand_in,
                                        starts_on: Date.current, ends_on: Date.current + 5)

    sign_in manager
    get "/hr/approvals"
    expect(response.body).to include("While you are away", "Priya")
  end

  it "flags a row that has sat past its deadline" do
    leave = leave!
    leave.approvals.first.update_column(:created_at, 3.days.ago)

    sign_in manager
    get "/hr/approvals"
    expect(response.body).to include("Overdue")
  end

  it "links straight to the screen that decides it" do
    leave = leave!
    sign_in manager
    get "/hr/approvals"

    expect(response.body).to include("/hr/admin/leave_requests/#{leave.id}")
  end
end

RSpec.describe HrLite::ApprovalEscalationJob, no_legacy_bridge: true do
  let!(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:leave_type) { create(:leave_type, code: "CL", annual_quota: 12) }

  around { |example| travel_to(Date.new(2027, 6, 17)) { example.run } }

  before do
    create(:employee_profile, user: employee, manager_id: manager.id)
    flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Leave")
    flow.approval_steps.create!(position: 1, approver_rule: "manager", sla_hours: 24)
  end

  def overdue_leave!
    leave = create(:leave_request, user: employee, leave_type: leave_type,
                                   start_date: Date.new(2027, 6, 21), end_date: Date.new(2027, 6, 21))
    leave.approvals.first.update_column(:created_at, 3.days.ago)
    leave
  end

  it "tells the approver, and stamps the row so it does not nag daily" do
    approval = overdue_leave!.approvals.first
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    described_class.perform_now
    expect(bells.map { |b| b[:kind] }).to include("approval.escalated")
    expect(approval.reload.escalated_at).to be_present

    bells.clear
    described_class.perform_now
    expect(bells).to be_empty
  end

    # One message per approver, however many rows they are sitting on.
    it "groups several overdue rows into a single message" do
      second = user_with_roles(HrLite::Role::EMPLOYEE, name: "Dev")
      create(:employee_profile, user: second, manager_id: manager.id)
      overdue_leave!
      leave = create(:leave_request, user: second, leave_type: leave_type,
                                     start_date: Date.new(2027, 6, 22), end_date: Date.new(2027, 6, 22))
      leave.approvals.first.update_column(:created_at, 4.days.ago)

      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      described_class.perform_now

      expect(bells.size).to eq(1)
      expect(bells.first[:title]).to include("2 approvals")
    end

  it "leaves a row inside its deadline alone" do
    create(:leave_request, user: employee, leave_type: leave_type,
                           start_date: Date.new(2027, 6, 21), end_date: Date.new(2027, 6, 21))
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    described_class.perform_now
    expect(bells).to be_empty
  end

  it "does nothing when a step has no deadline at all" do
    HrLite::ApprovalStep.update_all(sla_hours: nil)
    overdue_leave!
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    described_class.perform_now
    expect(bells).to be_empty
  end
end
