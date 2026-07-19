require "rails_helper"

RSpec.describe "Regularization tickets", type: :request do
  let(:user) { create(:user, name: "Dev") }
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let(:tuesday) { Date.new(2027, 7, 6) }

  around { |example| travel_to(Date.new(2027, 7, 8)) { example.run } }

  describe "employee flow" do
    before { sign_in user }

    it "raises a ticket and sees it listed" do
      expect {
        post "/hr/regularization_requests", params: {
          regularization_request: {
            date: tuesday, check_in_at: "2027-07-06T09:30", check_out_at: "2027-07-06T18:30",
            reason: "Forgot both punches"
          }
        }
      }.to change(HrLite::RegularizationRequest, :count).by(1)

      follow_redirect!
      expect(response.body).to include("Ticket raised").and include("09:30 – 18:30")
    end

    it "prefills the date from the query param" do
      get "/hr/regularization_requests/new", params: { date: "2027-07-06" }
      expect(response.body).to include(%(value="2027-07-06"))
    end

    it "re-renders with errors when no time is proposed" do
      post "/hr/regularization_requests", params: {
        regularization_request: { date: tuesday, reason: "Missed" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("check-in time, a check-out time")
    end

    it "cancels own pending ticket but 404s a foreign one" do
      mine = create(:regularization_request, user: user, date: tuesday)
      other = create(:regularization_request, date: tuesday)

      post "/hr/regularization_requests/#{other.id}/cancel"
      expect(response).to have_http_status(:not_found)

      post "/hr/regularization_requests/#{mine.id}/cancel"
      expect(mine.reload).to be_cancelled
    end

    it "refuses to cancel a decided ticket" do
      mine = create(:regularization_request, user: user, date: tuesday)
      mine.reject!(actor: admin, note: "no")
      post "/hr/regularization_requests/#{mine.id}/cancel"
      follow_redirect!
      expect(response.body).to include("Only pending tickets")
    end
  end

  describe "admin flow" do
    let!(:ticket) { create(:regularization_request, user: user, date: tuesday) }

    before { sign_in admin }

    it "lists pending with tabs and filters" do
      get "/hr/admin/regularization_requests"
      expect(response.body).to include("Dev").and include("Comp-off")

      get "/hr/admin/regularization_requests", params: { status: "rejected" }
      expect(response.body).to include("No rejected tickets")
    end

    it "shows the ticket and approves, fixing attendance" do
      get "/hr/admin/regularization_requests/#{ticket.id}"
      expect(response.body).to include("No punch recorded")

      post "/hr/admin/regularization_requests/#{ticket.id}/approve"
      follow_redirect!
      expect(response.body).to include("attendance fixed")
      record = HrLite::AttendanceRecord.find_by!(user_id: user.id, date: tuesday)
      expect(record.check_in_at).to eq(ticket.check_in_at)
      expect(record.regularization_note).to include("Ticket ##{ticket.id}")
    end

    it "explains an impossible merge instead of the wrong 'already decided' alert" do
      broken = create(:regularization_request, user: user, date: tuesday - 1, check_in_at: nil)
      post "/hr/admin/regularization_requests/#{broken.id}/approve"
      follow_redirect!
      expect(response.body).to include("Cannot apply").and include("no check-in")
      expect(broken.reload).to be_pending
    end

    it "shows a flagged existing punch on the ticket" do
      create(:attendance_record, :flagged, user: user, date: tuesday,
             check_in_at: tuesday.in_time_zone.change(hour: 9))
      get "/hr/admin/regularization_requests/#{ticket.id}"
      expect(response.body).to include("Flagged")
    end

    it "requires a note to reject, then rejects" do
      post "/hr/admin/regularization_requests/#{ticket.id}/reject", params: { decision_note: " " }
      follow_redirect!
      expect(response.body).to include("A note is required")

      post "/hr/admin/regularization_requests/#{ticket.id}/reject", params: { decision_note: "On leave that day" }
      expect(ticket.reload).to be_rejected
    end

    it "alerts on double decisions" do
      ticket.approve!(actor: admin)
      post "/hr/admin/regularization_requests/#{ticket.id}/approve"
      follow_redirect!
      expect(response.body).to include("Only pending tickets")

      post "/hr/admin/regularization_requests/#{ticket.id}/reject", params: { decision_note: "x" }
      follow_redirect!
      expect(response.body).to include("Only pending tickets")
    end

    it "keeps the admin screens away from non-admins" do
      sign_in user
      get "/hr/admin/regularization_requests"
      expect(response).to have_http_status(:redirect)
    end
  end
end
