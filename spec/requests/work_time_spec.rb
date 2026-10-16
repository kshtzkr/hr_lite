require "rails_helper"

RSpec.describe "My work time", type: :request do
  let(:asha) { create(:user, name: "Asha") }
  let(:dev) { create(:user, name: "Dev") }
  let(:day) { Date.new(2026, 10, 20) }

  def t(hour, min = 0) = Time.zone.local(2026, 10, 20, hour, min)
  def ev(user, mode, from, to, source: "employee") = HrLite::WorkModeEvent.create!(user_id: user.id, mode: mode, source: source, started_at: from, ended_at: to)

  before do
    HrLite.config.office_geofence = true
    travel_to(t(20))
    create(:attendance_record, user: asha, date: day, check_in_at: t(9), check_out_at: t(18))
    ev(asha, "office", t(9), t(18), source: "system")
    ev(asha, "lunch", t(13), t(13, 30))
    ev(dev, "wfh", t(9), t(17), source: "system")
    sign_in asha
  end

  after { travel_back }

  it "shows my own totals, matching the service, with the denominator stated" do
    get "/hr/work_time", params: { period: "day", date: day }
    result = HrLite::WorkModeDurations.call([ asha.id ], HrLite::WorkModeDurations::Period.build("day", day))
    kpis = Nokogiri::HTML(response.body).css(".hrl-kpi").to_h { |k| [ k.at_css(".hrl-kpi__label").text, k.at_css(".hrl-kpi__value").text ] }
    # Breaks count as working: a 9h day with a 30 min lunch is 9h of working time.
    expect(kpis).to include("Working time (breaks included)" => format("%dh %02dm", (result.working + result.breaks) / 3600, ((result.working + result.breaks) % 3600) / 60),
                            "Of which breaks" => "0h 30m")
    expect(kpis["Working time (breaks included)"]).to eq("9h 00m")
    expect(response.body).to include("Shares are of tracked time").and include("<title>Lunch break")
  end

  it "ignores any user param — nobody reads someone else's time here" do
    get "/hr/work_time", params: { period: "day", date: day, user_id: dev.id }
    expect(response.body).not_to include("Work from home</td>")
    expect(response.body).to include("Lunch break")
  end

  it "draws weekly bars that link to each day, and refuses a bad custom range" do
    get "/hr/work_time", params: { period: "week", date: day }
    expect(response.body).to include("hrl-bars").and include("date=2026-10-20&amp;period=day")
    get "/hr/work_time", params: { period: "custom", from: "2026-10-20", to: "2026-10-01" }
    expect(response.body).to include("The start date is after the end date.")
  end

  it "says there is no data rather than showing zeros" do
    get "/hr/work_time", params: { period: "day", date: day - 3 }
    expect(response.body).to include("No recorded activity")
  end
end
