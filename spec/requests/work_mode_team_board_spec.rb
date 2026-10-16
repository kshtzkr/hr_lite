require "rails_helper"

RSpec.describe "Team board work modes", type: :request do
  let(:asha) { create(:user, name: "Asha") }
  let(:dev) { create(:user, name: "Dev") }
  let(:ravi) { create(:user, name: "Ravi") }

  before do
    HrLite.config.office_geofence = true
    travel_to(Time.zone.local(2026, 10, 20, 11, 0))
    create(:employee_profile, user: asha, department: "Sales")
    create(:employee_profile, user: dev, department: "Ops")
    create(:employee_profile, user: ravi, department: "Ops")
    home = HrLite::WorkLocation.create!(user_id: asha.id, name: "Home", lat: 28.5355, lng: 77.391, accuracy_m: 20,
                                        address: "Flat 4, Sector 18", status: "approved", active: true)
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "wfh", source: "system", work_location_id: home.id, started_at: 2.hours.ago)
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "busy", source: "employee", ends_at: 1.hour.from_now)
    HrLite::WorkModeEvent.start!(user_id: dev.id, mode: "travelling", source: "employee", destination: "Acme Gurgaon", title: "Pitch")
    sign_in ravi
  end

  after { travel_back }

  it "shows each person's icons and a general place, never the home address or trip details" do
    get "/hr/team"
    expect(response.body).to include("hrl-mode--wfh").and include("hrl-mode--busy").and include("hrl-mode--travelling")
    expect(response.body).to include("Home · Busy").and include("until 12:00")
    # Ravi is offline and Not in yet: the phone card skips the Now row that only repeats it.
    expect(Nokogiri::HTML(response.body).css('td[data-label="Now"]').map { |td| td["class"] }.count("hrl-cell--void")).to eq(1)
    expect(response.body).not_to include("Sector 18")
    expect(response.body).not_to include("28.5355")
    expect(response.body).not_to include("Acme Gurgaon")
  end

  it "filters by department, mode and availability" do
    get "/hr/team", params: { department: "Ops" }
    expect(response.body).to include("Dev").and include("Ravi")
    expect(response.body).not_to include(">Asha<")

    get "/hr/team", params: { mode: "busy" }
    expect(response.body).to include("Asha")
    expect(response.body).not_to include("Dev</strong>")

    get "/hr/team", params: { availability: "available" }
    expect(response.body).to include("Dev</strong>")
    expect(response.body).not_to include("Ravi</strong>")
  end
end
