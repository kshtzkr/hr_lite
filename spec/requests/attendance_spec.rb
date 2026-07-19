require "rails_helper"

RSpec.describe "Attendance", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /hr/attendance" do
    it "requires sign-in" do
      sign_out
      get "/hr/attendance"
      expect(response).to have_http_status(:unauthorized)
    end

    it "renders the punch card and month grid" do
      get "/hr/attendance"
      expect(response.body).to include("Check in").and include(Date.current.strftime("%B %Y"))
    end

    it "renders a requested month and falls back on garbage" do
      get "/hr/attendance", params: { month: "2026-05" }
      expect(response.body).to include("May 2026")

      get "/hr/attendance", params: { month: "nonsense" }
      expect(response.body).to include(Date.current.strftime("%B %Y"))
    end
  end

  describe "POST /hr/attendance/check_in" do
    it "records the punch with geolocation" do
      post "/hr/attendance/check_in", params: { lat: "28.6", lng: "77.2", accuracy_m: "12", geo_status: "ok" }

      expect(response).to redirect_to("/hr/attendance")
      follow_redirect!
      expect(response.body).to include("Checked in at")
      record = HrLite::AttendanceRecord.last
      expect(record.user_id).to eq(user.id)
      expect(record.check_in_lat).to eq(28.6)
    end

    it "records but flags a GPS-denied punch" do
      post "/hr/attendance/check_in", params: { geo_status: "denied" }
      expect(HrLite::AttendanceRecord.last.flag_note).to include("without GPS (denied)")
    end

    it "surfaces duplicate-punch errors as alerts" do
      post "/hr/attendance/check_in", params: { geo_status: "ok", lat: "1", lng: "1" }
      post "/hr/attendance/check_in", params: { geo_status: "ok", lat: "1", lng: "1" }
      expect(flash[:alert]).to include("Already checked in")
    end
  end

  describe "POST /hr/attendance/check_out" do
    it "closes the day" do
      post "/hr/attendance/check_in", params: { geo_status: "ok", lat: "1", lng: "1" }
      post "/hr/attendance/check_out", params: { geo_status: "ok", lat: "1", lng: "1" }
      expect(HrLite::AttendanceRecord.last.check_out_at).to be_present
    end

    it "alerts when there is nothing to close" do
      post "/hr/attendance/check_out", params: { geo_status: "ok" }
      expect(flash[:alert]).to eq("No open check-in to close.")
    end
  end
end
