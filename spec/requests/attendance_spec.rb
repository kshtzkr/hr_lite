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

    describe "month grid states" do
      before do
        travel_to(Date.new(2026, 10, 1))
        type = create(:leave_type)
        create(:leave_request, :approved, user: user, leave_type: type,
               start_date: Date.new(2026, 10, 16), end_date: Date.new(2026, 10, 16))
        create(:leave_request, :approved, user: user, leave_type: type,
               start_date: Date.new(2026, 10, 19), end_date: Date.new(2026, 10, 19), half_day_part: "first")
        get "/hr/attendance", params: { month: "2026-10" }
      end

      after { travel_back }

      it "names each day in words and keys every code in the legend" do
        expect(response.body).to include('aria-label="16 Oct, Leave"').and include("WO Weekly off")
      end

      it "does not paint a half-day leave as a full one" do
        cell = Nokogiri::HTML(response.body).at_css('[aria-label="19 Oct, Half-day leave"]')
        expect(cell["class"].split).to include("hrl-mgrid__day--half-leave")
        expect(cell["class"].split).not_to include("hrl-mgrid__day--leave")
      end
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
