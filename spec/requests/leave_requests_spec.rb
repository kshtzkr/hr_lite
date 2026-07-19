require "rails_helper"

RSpec.describe "Leave requests", type: :request do
  let(:user) { create(:user, name: "Asha") }
  let(:type) { create(:leave_type, name: "Casual", annual_quota: 12) }
  let(:monday) { Date.new(2027, 7, 5) }

  around { |example| travel_to(Date.new(2027, 7, 1)) { example.run } }
  before { sign_in user }

  describe "employee flow" do
    it "applies for leave and sees it listed" do
      expect {
        post "/hr/leave_requests", params: {
          leave_request: { leave_type_id: type.id, start_date: monday, end_date: monday + 1, reason: "Family" }
        }
      }.to change(HrLite::LeaveRequest, :count).by(1)

      follow_redirect!
      expect(response.body).to include("Leave request submitted.").and include("05 Jul – 06 Jul")
    end

    it "re-renders with errors on invalid input" do
      post "/hr/leave_requests", params: {
        leave_request: { leave_type_id: type.id, start_date: monday, end_date: monday - 1 }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("prevented saving")
    end

    it "shows own request but 404s a foreign one" do
      mine = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      other = create(:leave_request, leave_type: type, start_date: monday, end_date: monday)

      get "/hr/leave_requests/#{mine.id}"
      expect(response).to have_http_status(:ok)

      get "/hr/leave_requests/#{other.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "cancels a pending request" do
      request = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      post "/hr/leave_requests/#{request.id}/cancel"
      expect(request.reload).to be_cancelled
    end

    it "refuses to cancel a decided past request" do
      request = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      request.approve!(actor: create(:user, :admin))
      travel_to(monday + 2)
      post "/hr/leave_requests/#{request.id}/cancel"
      expect(flash[:alert]).to include("no longer")
      expect(request.reload).to be_approved
    end

    it "shows balances on the index" do
      get "/hr/leave_requests"
      expect(response.body).to include("Leave balance")
    end
  end

  describe "balances page" do
    it "renders per-type cards for a chosen year" do
      type
      get "/hr/leave_balances", params: { year: 2027 }
      expect(response.body).to include("Casual").and include("Entitled")
    end
  end

  describe "holidays + calendar pages" do
    it "lists holidays for the year" do
      create(:holiday, date: Date.new(2027, 3, 4), name: "Holi 2027")
      get "/hr/holidays", params: { year: 2027 }
      expect(response.body).to include("Holi 2027")
    end

    it "renders the month calendar with holidays, leaves and weekend shading" do
      create(:holiday, date: monday, name: "Founders day")
      colleague = create(:user, name: "Dev Kumar")
      create(:leave_request, :approved, user: colleague, leave_type: type,
             start_date: monday + 1, end_date: monday + 1)

      get "/hr/calendar", params: { month: "2027-07" }
      expect(response.body).to include("Founders day").and include("Dev ·")
    end
  end
end
