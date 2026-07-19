require "rails_helper"

RSpec.describe "Comp-off requests", type: :request do
  let(:user) { create(:user, name: "Meera") }
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let!(:co_type) { create(:leave_type, :comp_off, code: "CO", name: "Comp off") }
  let(:sunday) { Date.new(2027, 7, 4) }

  around { |example| travel_to(Date.new(2027, 7, 7)) { example.run } }

  describe "employee flow" do
    before { sign_in user }

    it "requests comp-off for a worked Sunday and sees it listed" do
      expect {
        post "/hr/comp_off_requests", params: {
          comp_off_request: { date_worked: sunday, half_day: "0", reason: "Departure desk" }
        }
      }.to change(HrLite::CompOffRequest, :count).by(1)

      follow_redirect!
      expect(response.body).to include("Comp-off request sent").and include("Sun, 04 Jul 2027")
    end

    it "re-renders with the policy error for a working day" do
      post "/hr/comp_off_requests", params: {
        comp_off_request: { date_worked: Date.new(2027, 7, 5), reason: "Long day" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("regular working day")
    end

    it "prefills the form with the latest off day" do
      get "/hr/comp_off_requests/new"
      expect(response.body).to include(%(value="2027-07-04"))
    end

    it "cancels own pending request but 404s a foreign one" do
      mine = create(:comp_off_request, user: user, date_worked: sunday)
      other = create(:comp_off_request, date_worked: sunday)

      post "/hr/comp_off_requests/#{other.id}/cancel"
      expect(response).to have_http_status(:not_found)

      post "/hr/comp_off_requests/#{mine.id}/cancel"
      expect(mine.reload).to be_cancelled
    end

    it "refuses to cancel a decided request" do
      mine = create(:comp_off_request, user: user, date_worked: sunday)
      mine.approve!(actor: admin)
      post "/hr/comp_off_requests/#{mine.id}/cancel"
      follow_redirect!
      expect(response.body).to include("Only pending requests")
      expect(mine.reload).to be_approved
    end
  end

  describe "admin flow" do
    let!(:request_row) { create(:comp_off_request, user: user, date_worked: sunday) }

    before { sign_in admin }

    it "lists pending by default with the approvals tabs, filters by status" do
      get "/hr/admin/comp_off_requests"
      expect(response.body).to include("Meera").and include("Regularization")

      get "/hr/admin/comp_off_requests", params: { status: "approved" }
      expect(response.body).to include("No approved comp-off requests")
    end

    it "shows the punch context and approves, crediting the balance" do
      create(:attendance_record, user: user, date: sunday,
             check_in_at: sunday.in_time_zone.change(hour: 10),
             check_out_at: sunday.in_time_zone.change(hour: 16))

      get "/hr/admin/comp_off_requests/#{request_row.id}"
      expect(response.body).to include("10:00–16:00")

      post "/hr/admin/comp_off_requests/#{request_row.id}/approve"
      follow_redirect!
      expect(response.body).to include("1.0 day credited")
      expect(HrLite::LeaveBalance.for(user, co_type, 2027).adjustment).to eq(1)
    end

    it "notes the missing punch for the approver" do
      get "/hr/admin/comp_off_requests/#{request_row.id}"
      expect(response.body).to include("No punch recorded")
    end

    it "surfaces the missing comp-off type instead of crashing" do
      co_type.update!(comp_off: false)
      post "/hr/admin/comp_off_requests/#{request_row.id}/approve"
      follow_redirect!
      expect(response.body).to include("No active leave type is marked as comp-off")
      expect(request_row.reload).to be_pending
    end

    it "requires a note to reject, then rejects" do
      post "/hr/admin/comp_off_requests/#{request_row.id}/reject", params: { decision_note: "" }
      follow_redirect!
      expect(response.body).to include("A note is required")

      post "/hr/admin/comp_off_requests/#{request_row.id}/reject", params: { decision_note: "Not pre-agreed" }
      expect(request_row.reload).to be_rejected
    end

    it "alerts on double decisions" do
      request_row.approve!(actor: admin)
      post "/hr/admin/comp_off_requests/#{request_row.id}/approve"
      follow_redirect!
      expect(response.body).to include("Only pending requests")

      post "/hr/admin/comp_off_requests/#{request_row.id}/reject", params: { decision_note: "x" }
      follow_redirect!
      expect(response.body).to include("Only pending requests")
    end

    it "keeps the decide screens away from non-admins" do
      sign_in user
      get "/hr/admin/comp_off_requests"
      expect(response).to have_http_status(:redirect)
    end
  end
end
