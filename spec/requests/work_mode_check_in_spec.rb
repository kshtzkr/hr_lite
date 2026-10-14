require "rails_helper"

RSpec.describe "Check-in decides the work mode", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:office) { { lat: "28.6130", lng: "77.36606", accuracy_m: "20", geo_status: "ok" } }
  let(:home) { { lat: "28.5355", lng: "77.3910", accuracy_m: "20", geo_status: "ok" } }
  let(:near_home) { home.merge(lat: "28.5390") } # ~390 m
  let(:far_from_home) { home.merge(lat: "28.5455") } # ~1.1 km
  let(:client_site) { { lat: "19.0760", lng: "72.8777", accuracy_m: "30", geo_status: "ok" } }
  let!(:profile) { create(:employee_profile, user: employee) }

  before do
    HrLite.config.office_geofence = true
    create(:office_location, name: "Head office", lat: 28.61270779585808, lng: 77.36605830864376, radius_m: 500)
    sign_in employee
  end

  def record = HrLite::AttendanceRecord.find_by(user_id: employee.id, date: Date.current)
  def approve_wfh = HrLite::WfhRequest.new(user_id: employee.id, start_date: Date.current, end_date: Date.current, reason: "x", status: "approved").tap { |r| r.save!(validate: false) }
  def register_home(status: "approved", active: true) = HrLite::WorkLocation.create!(user_id: employee.id, name: "Home", lat: 28.5355, lng: 77.3910, accuracy_m: 20, status: status, active: active)

  it "is office inside the office radius" do
    post "/hr/attendance/check_in", params: office
    expect(record.work_mode).to eq("office")
  end

  it "is WFH within 500 m of the approved home on an approved WFH day" do
    approve_wfh
    location = register_home
    post "/hr/attendance/check_in", params: near_home
    expect(record).to have_attributes(work_mode: "wfh", work_location_id: location.id)
  end

  it "refuses WFH check-in away from the registered home, asking if this is home" do
    approve_wfh
    register_home
    post "/hr/attendance/check_in", params: far_from_home
    expect(flash[:alert]).to eq(HrLite::AttendancePuncher::HOME_ASK_MESSAGE)
    expect(flash[:punch_offer]).to eq("home")
    expect(record).to be_nil
  end

  it "never lets a home location alone grant WFH, nor a pending location count" do
    register_home
    post "/hr/attendance/check_in", params: home
    expect(flash[:alert]).to eq(HrLite::AttendancePuncher::OFF_SITE_MESSAGE)

    HrLite::WorkLocation.delete_all
    approve_wfh
    register_home(status: "pending", active: false)
    post "/hr/attendance/check_in", params: home
    expect(flash[:alert]).to eq(HrLite::AttendancePuncher::HOME_ASK_MESSAGE)
    expect(record).to be_nil
  end

  it "lets field staff check in anywhere as travelling or a client meeting, with purpose and place" do
    profile.update!(field_staff: true)
    post "/hr/attendance/check_in", params: client_site.merge(field: { mode: "outside_meeting", purpose: "Demo" })
    expect(flash[:alert]).to include("why and where")

    post "/hr/attendance/check_in", params: client_site.merge(field: { mode: "outside_meeting", purpose: "Demo", place: "Acme Mumbai" })
    expect(record).to have_attributes(work_mode: "outside_meeting")
    expect(record).not_to be_flagged
  end

  it "refuses a field check-in from someone who is not field staff" do
    post "/hr/attendance/check_in", params: client_site.merge(field: { mode: "travelling", purpose: "Visit", place: "Mumbai" })
    expect(flash[:alert]).to eq(HrLite::AttendancePuncher::OFF_SITE_MESSAGE)
  end

  it "keeps check-out working as before" do
    post "/hr/attendance/check_in", params: office
    post "/hr/attendance/check_out", params: home
    expect(record.check_out_at).to be_present
    expect(record.work_mode).to eq("office")
  end
end
