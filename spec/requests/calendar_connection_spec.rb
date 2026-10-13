require "rails_helper"

RSpec.describe "Connect Google Calendar button", type: :request do
  let(:asha) { create(:user, name: "Asha") }

  before do
    HrLite.config.office_geofence = true
    sign_in asha
  end

  it "offers one-click connect, then shows the connected calendar with a disconnect" do
    HrLite.config.calendar_connection = ->(_u) { { connected: false, connect_url: "/calendar/connect" } }
    get "/hr/attendance"
    expect(response.body).to include(%(href="/calendar/connect")).and include("Connect Google Calendar")

    HrLite.config.calendar_connection = ->(_u) { { connected: true, label: "asha@gmail.com", disconnect_url: "/calendar/connection" } }
    get "/hr/attendance"
    expect(response.body).to include("Calendar connected").and include("asha@gmail.com").and include(%(action="/calendar/connection"))
  end

  it "shows nothing when the host has no calendar link" do
    get "/hr/attendance"
    expect(response.body).not_to include("Connect Google Calendar")
  end
end
