require "rails_helper"

RSpec.describe "Approval gaps", type: :request do
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let(:employee) { create(:user, name: "Meera") }
  let(:leave_type) { create(:leave_type, code: "CL", name: "Casual", annual_quota: 12) }

  describe "regularization approved after leave was granted for the same day" do
    # The conflict check was create-only, so leave approved while the ticket
    # waited made the fix a silent no-op: DayStatus ranks full-day leave above
    # any punch, yet everyone was told attendance had been corrected.
    it "refuses the merge instead of writing a record nothing reads" do
      date = Date.current - 3
      ticket = create(:regularization_request, user: employee, date: date,
                      check_in_at: date.in_time_zone.change(hour: 10),
                      check_out_at: date.in_time_zone.change(hour: 19))
      create(:leave_request, :approved, user: employee, leave_type: leave_type,
             start_date: date, end_date: date)

      sign_in admin
      post "/hr/admin/regularization_requests/#{ticket.id}/approve"

      expect(ticket.reload).to be_pending
      expect(flash[:alert]).to include("covered by approved leave")
      expect(HrLite::AttendanceRecord.find_by(user_id: employee.id, date: date)).to be_nil
    end
  end

  describe "an admin calling off approved leave" do
    let!(:request_row) do
      create(:leave_request, :approved, user: employee, leave_type: leave_type,
             start_date: Date.current + 10, end_date: Date.current + 12)
    end

    it "cancels it and releases the balance" do
      sign_in admin
      post "/hr/admin/leave_requests/#{request_row.id}/cancel"

      expect(request_row.reload.status).to eq("cancelled")
      expect(flash[:notice]).to include("balance is released")
    end

    it "offers the control on the decision screen" do
      sign_in admin
      get "/hr/admin/leave_requests/#{request_row.id}"

      expect(response.body).to include("Cancel this leave")
    end

    it "refuses once the leave has started" do
      started = create(:leave_request, :approved, user: employee, leave_type: leave_type,
                       start_date: Date.current - 1, end_date: Date.current + 1)

      sign_in admin
      post "/hr/admin/leave_requests/#{started.id}/cancel"

      expect(started.reload.status).to eq("approved")
      expect(flash[:alert]).to include("cannot be cancelled").or include("can be cancelled")
    end
  end

  describe "the audit trail" do
    # Written from after_*_commit: fired inside the transaction it announced
    # changes to leadership that were then rolled back.
    # The audit ROW would roll back either way. What used to escape is the
    # announcement: policy.changed mails leadership a diff, and mail is not
    # transactional, so a rolled-back change was still reported as made.
    it "announces nothing for a change that rolls back" do
      published = []
      allow(HrLite::Notifications).to receive(:publish) { |event, **| published << event.to_s }

      ActiveRecord::Base.transaction do
        create(:leave_type, code: "XX", name: "Rolled back", annual_quota: 1)
        raise ActiveRecord::Rollback
      end

      expect(published).not_to include("policy.changed")
    end

    it "still records a change that commits" do
      expect {
        create(:leave_type, code: "YY", name: "Kept", annual_quota: 1)
      }.to change(HrLite::AuditLog, :count).by(1)
    end
  end
end
