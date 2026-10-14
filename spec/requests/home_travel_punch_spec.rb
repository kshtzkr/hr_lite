require "rails_helper"

RSpec.describe "Home detection and travel punches", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:office) { { lat: "28.6130", lng: "77.36606", accuracy_m: "20", geo_status: "ok" } }
  let(:home) { { lat: "28.5355", lng: "77.3910", accuracy_m: "20", geo_status: "ok" } }
  let(:away) { home.merge(lat: "28.5455") } # ~1.1 km from home
  let!(:profile) { create(:employee_profile, user: employee, permanent_wfh: true) }

  before do
    HrLite.config.office_geofence = true
    create(:office_location, name: "Head office", lat: 28.61270779585808, lng: 77.36605830864376, radius_m: 500)
    sign_in employee
  end

  def record = HrLite::AttendanceRecord.find_by(user_id: employee.id, date: Date.current)
  def homes = HrLite::WorkLocation.where(user_id: employee.id)
  def add_home(lat, active: false) = homes.create!(name: "Home", lat: lat, lng: 77.3910, accuracy_m: 20, status: "approved", active: active)

  it "picks whichever approved home covers the fix and makes it the active one" do
    add_home(28.60, active: true)
    flat = add_home(28.5355)
    post "/hr/attendance/check_in", params: home
    expect(record).to have_attributes(work_mode: "wfh", check_in_place: "home", work_location_id: flat.id, check_in_home_m: 0)
    expect(flat.reload).to be_active
  end

  it "asks whether an uncovered spot is home, and saves nothing until told yes" do
    post "/hr/attendance/check_in", params: home
    expect(flash[:alert]).to eq(HrLite::AttendancePuncher::HOME_ASK_MESSAGE)
    expect(flash[:punch_offer]).to eq("home")
    expect([ record, homes.count ]).to eq([ nil, 0 ])

    post "/hr/attendance/check_in", params: home.merge(save_home: "1")
    saved = homes.sole
    expect(saved).to have_attributes(name: "Home 1", status: "approved", active: true)
    expect(record).to have_attributes(check_in_place: "home", work_location_id: saved.id)
    expect(HrLite::AuditLog.where(action: "work_location.self_saved").count).to eq(1)
  end

  it "will not save a home from a vague fix or past three live homes" do
    post "/hr/attendance/check_in", params: home.merge(accuracy_m: "600", save_home: "1")
    expect(flash[:alert]).to eq(HrLite::AttendancePuncher::HOME_FIX_MESSAGE)

    3.times { |i| add_home(27.0 + i) }
    post "/hr/attendance/check_in", params: home.merge(save_home: "1")
    expect(flash[:alert]).to eq(HrLite::AttendancePuncher::HOME_CAP_MESSAGE)
    expect([ record, homes.count ]).to eq([ nil, 3 ])
  end

  it "lets a WFH employee who is not field staff check in travelling, with distance from home" do
    add_home(28.5355)
    post "/hr/attendance/check_in", params: away.merge(place: "travel")
    expect(record).to have_attributes(work_mode: "travelling", check_in_place: "travel")
    expect(record.check_in_home_m).to be_within(50).of(1112)
  end

  it "needs Travelling picked to check out away from home after a home check-in" do
    add_home(28.5355)
    post "/hr/attendance/check_in", params: home
    post "/hr/attendance/check_out", params: away
    expect(flash[:alert]).to eq(HrLite::AttendancePuncher::TRAVEL_OUT_MESSAGE)
    expect(flash[:punch_offer]).to eq("travel")
    expect(record.check_out_at).to be_nil

    post "/hr/attendance/check_out", params: away.merge(place: "travel")
    expect(record).to have_attributes(check_in_place: "home", check_out_place: "travel", check_out_work_location_id: nil)
    expect(record.check_out_home_m).to be > 1000
  end

  it "ends a travel day at home without asking, and records the office for office staff" do
    flat = add_home(28.5355)
    post "/hr/attendance/check_in", params: away.merge(place: "travel")
    post "/hr/attendance/check_out", params: home
    expect(record).to have_attributes(check_out_place: "home", check_out_work_location_id: flat.id)

    profile.update!(permanent_wfh: false)
    record.destroy
    post "/hr/attendance/check_in", params: office
    post "/hr/attendance/check_out", params: away
    expect(record.reload).to have_attributes(check_in_place: "office", check_out_place: nil)
  end
end

RSpec.describe "Home and travel on screen", type: :request do
  let(:employee) { create(:user, name: "Asha Rao") }
  let(:admin) { create(:user, :admin) }
  let(:home) { { lat: "28.5355", lng: "77.3910", accuracy_m: "20", geo_status: "ok" } }
  let(:away) { home.merge(lat: "28.5455", accuracy_m: "30") }

  before do
    HrLite.config.office_geofence = true
    create(:office_location, lat: 28.61270779585808, lng: 77.36605830864376, radius_m: 500)
    create(:employee_profile, user: employee, permanent_wfh: true)
    sign_in employee
  end

  it "puts the home question, then the travelling box, on the punch card" do
    post "/hr/attendance/check_in", params: home
    follow_redirect!
    expect(response.body).to include("Is this your home location?", %(value="home"), %(value="travel"))

    post "/hr/attendance/check_in", params: home.merge(place: "home")
    get "/hr/attendance"
    expect(response.body).to include("Home 1 · 500 m")
    expect(response.body).not_to include("Is this your home location?")

    post "/hr/attendance/check_out", params: away
    follow_redirect!
    expect(response.body).to include("I am travelling — check out here")
  end

  it "shows the day's trail to the employee, HR and the home page" do
    post "/hr/attendance/check_in", params: home.merge(place: "home")
    post "/hr/attendance/check_out", params: away.merge(place: "travel")
    route = "https://www.google.com/maps/dir/?api=1&amp;origin=28.5355,77.391&amp;destination=28.5455,77.391"

    get "/hr/work_time", params: { period: "day" }
    expect(response.body).to include("Check-in: Home (Home 1)", "0 m from home", "±20 m", "Check-out: Travel", "1,112 m from home", route)

    sign_in admin
    get "/hr/admin/attendances/#{employee.id}"
    expect(response.body).to include("Check-in: Home (Home 1)", "Check-out: Travel", "View route on Google Maps")
    get "/hr"
    expect(response.body).to include("Check-in: Home → Check-out: Travel")
  end
end
