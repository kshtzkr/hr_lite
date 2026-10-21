require "rails_helper"

RSpec.describe "Work-mode screens: edges", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:asha) { create(:user, name: "Asha") }

  before { HrLite.config.office_geofence = true }

  it "lets HR set a slot, and says why a bad one fails" do
    sign_in admin
    post "/hr/admin/attendances/#{asha.id}/slot", params: { start_minute: 570, period: "week" }
    expect(flash[:notice]).to eq("Slot set to 09:30.")
    post "/hr/admin/attendances/#{asha.id}/slot", params: { start_minute: 123, period: "week" }
    expect(flash[:alert]).to include("Start minute")
  end

  it "refuses a slot the employee can't pick" do
    HrLite.config.attendance_slots = true
    sign_in asha
    post "/hr/attendance/slot", params: { start_minute: 123, period: "day" }
    expect(flash[:alert]).to include("Start minute")
  end

  it "announces an office holiday only to that office" do
    noida = create(:office_location, name: "Noida")
    inside = create(:employee_profile, office_location: noida).user
    outside = create(:employee_profile).user
    sign_in admin
    told = []
    allow(HrLite::Notifications).to receive(:publish) { |_e, **o| told.concat(o[:bell_to]) }
    post "/hr/admin/holidays", params: { holiday: { date: "2026-11-02", name: "Office day", office_location_id: noida.id } }
    expect(told).to include(inside)
    expect(told).not_to include(outside)
  end

  describe "WFH" do
    let(:request_row) do
      HrLite::WfhRequest.new(user_id: asha.id, start_date: Date.current, end_date: Date.current, reason: "x", status: "pending")
                        .tap { |r| r.save!(validate: false) }
    end

    it "shows a request to HR and refuses to decide it twice" do
      sign_in admin
      get "/hr/admin/wfh_requests/#{request_row.id}"
      expect(response.body).to include("Approve WFH")
      request_row.update_columns(status: "approved")
      post "/hr/admin/wfh_requests/#{request_row.id}/approve"
      expect(flash[:alert]).to include("Only pending")
    end

    it "lets the employee cancel a pending request once" do
      sign_in asha
      post "/hr/wfh_requests/#{request_row.id}/cancel"
      expect(request_row.reload).to be_cancelled
      post "/hr/wfh_requests/#{request_row.id}/cancel"
      expect(flash[:alert]).to include("Only pending")
    end
  end

  describe "WFH locations" do
    let!(:location) { HrLite::WorkLocation.create!(user_id: asha.id, name: "Home", lat: 1, lng: 1, accuracy_m: 10) }

    it "lists my locations and removes one" do
      sign_in asha
      get "/hr/work_locations"
      expect(response.body).to include("Home")
      post "/hr/work_locations/#{location.id}/remove"
      expect(location.reload).to be_removed
    end

    it "still saves a location when the HR notification fails" do
      allow(HrLite::Notifications).to receive(:publish).and_raise("down")
      sign_in asha
      post "/hr/work_locations", params: { name: "Parents", lat: "2", lng: "2", accuracy_m: "20" }
      expect(HrLite::WorkLocation.where(name: "Parents")).to exist
      expect(HrLite::AuditLog.find_by(action: "failure.work_location.requested").subject_id).to eq(asha.id)
    end

    it "shows HR the queue, decides once, and survives a failed notification" do
      sign_in admin
      get "/hr/admin/work_locations"
      expect(response.body).to include("Home")
      allow(HrLite::Notifications).to receive(:publish).and_raise("down")
      post "/hr/admin/work_locations/#{location.id}/approve"
      expect(location.reload).to be_approved
      expect(HrLite::AuditLog.find_by(action: "failure.work_location.approved").subject_id).to eq(location.user_id)
      post "/hr/admin/work_locations/#{location.id}/approve"
      expect(flash[:alert]).to include("Only pending")
    end
  end
end
