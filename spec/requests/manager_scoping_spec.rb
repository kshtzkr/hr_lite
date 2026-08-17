require "rails_helper"

# The gap roles exist to close. Before this, EVERY admin screen was reachable
# by every admin and acted on `Model.find(params[:id])` — so anybody who could
# approve leave could approve ANYBODY's leave. `manager_id` existed on the
# profile and drove nothing but the org chart.
#
# A manager reaching for somebody else's report gets a 404, not a 403: the
# same shape the employee-tier screens already use, and it does not confirm
# that the other person exists.
RSpec.describe "A manager reaches their own reports and no further", type: :request do
  let(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let(:other_manager) { user_with_roles(HrLite::Role::MANAGER, name: "Bilal") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }

  let!(:report) { create(:employee_profile, manager_id: manager.id).user }
  let!(:stranger) { create(:employee_profile, manager_id: other_manager.id).user }

  let(:leave_type) { create(:leave_type, code: "CL", name: "Casual", annual_quota: 12) }

  def leave_for(user)
    create(:leave_request, user: user, leave_type: leave_type,
                           start_date: Date.current + 8, end_date: Date.current + 8)
  end

  describe "the leave queue" do
    it "lists a report's request and not a stranger's" do
      mine = leave_for(report)
      theirs = leave_for(stranger)

      sign_in manager
      get "/hr/admin/leave_requests"

      expect(response.body).to include(HrLite.display_name(report))
      expect(response.body).not_to include(HrLite.display_name(stranger))
      expect(assigns_ids).to contain_exactly(mine.id)
      expect(assigns_ids).not_to include(theirs.id)
    end

    it "shows everyone's to HR" do
      leave_for(report)
      leave_for(stranger)

      sign_in hr
      get "/hr/admin/leave_requests"

      expect(response.body).to include(HrLite.display_name(report),
                                       HrLite.display_name(stranger))
    end
  end

  describe "deciding" do
    it "approves a report's leave" do
      leave = leave_for(report)

      sign_in manager
      post "/hr/admin/leave_requests/#{leave.id}/approve"

      expect(leave.reload).to be_approved
      expect(leave.decided_by_id).to eq(manager.id)
    end

    it "cannot even open a stranger's request" do
      leave = leave_for(stranger)

      sign_in manager
      get "/hr/admin/leave_requests/#{leave.id}"

      expect(response).to have_http_status(:not_found)
    end

    it "cannot approve, reject or cancel a stranger's leave" do
      leave = leave_for(stranger)
      sign_in manager

      post "/hr/admin/leave_requests/#{leave.id}/approve"
      expect(response).to have_http_status(:not_found)

      post "/hr/admin/leave_requests/#{leave.id}/reject", params: { decision_note: "no" }
      expect(response).to have_http_status(:not_found)

      post "/hr/admin/leave_requests/#{leave.id}/cancel"
      expect(response).to have_http_status(:not_found)

      expect(leave.reload).to be_pending
    end
  end

  describe "attendance" do
    it "opens a report's month but not a stranger's" do
      sign_in manager

      get "/hr/admin/attendances/#{report.id}"
      expect(response).to have_http_status(:ok)

      get "/hr/admin/attendances/#{stranger.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "refuses to rewrite a stranger's punches" do
      sign_in manager
      date = Date.current - 1

      patch "/hr/admin/attendances/#{stranger.id}", params: {
        date: date.to_s,
        attendance_record: { check_in_at: date.in_time_zone.change(hour: 10),
                             regularization_note: "trust me" }
      }

      expect(response).to have_http_status(:not_found)
      expect(HrLite::AttendanceRecord.find_by(user_id: stranger.id, date: date)).to be_nil
    end

    it "lists only reports on the day board" do
      sign_in manager
      get "/hr/admin/attendances"

      expect(response.body).to include(HrLite.display_name(report))
      expect(response.body).not_to include(HrLite.display_name(stranger))
    end
  end

  describe "reach beyond leave and attendance" do
    it "cannot govern people or policy" do
      sign_in manager

      get "/hr/admin/employees"
      expect(response).to redirect_to("/hr/")

      get "/hr/admin/leave_types"
      expect(response).to redirect_to("/hr/")
    end

    it "cannot reach payroll at all" do
      sign_in manager

      get "/hr/admin/payroll_runs"
      expect(response).to redirect_to("/hr/")
    end
  end

  describe "an indirect report" do
    # A skip-level manager reaches everyone below them, not just the people
    # who report to them directly.
    it "is reachable through the chain" do
      # `report` already reports to the manager; this hangs a third person
      # off `report`, so the manager reaches them only via the walk.
      grandchild = create(:employee_profile, manager_id: report.id).user
      leave = leave_for(grandchild)

      sign_in manager
      post "/hr/admin/leave_requests/#{leave.id}/approve"

      expect(leave.reload).to be_approved
    end
  end

  def assigns_ids
    HrLite::LeaveRequest.where(status: "pending").select do |leave|
      response.body.include?(HrLite.display_name(leave.user))
    end.map(&:id)
  end
end
