require "rails_helper"

RSpec.describe "HR work-modes board", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:asha) { create(:user, name: "Asha") }
  let(:dev) { create(:user, name: "Dev") }
  let(:ravi) { create(:user, name: "Ravi") }

  before do
    HrLite.config.office_geofence = true
    travel_to(Time.zone.local(2026, 10, 20, 11, 0))
    { asha => "Sales", dev => "Sales", ravi => "Ops" }.each { |u, d| create(:employee_profile, user: u, department: d) }
    rec = create(:attendance_record, user: asha, date: Date.current, check_in_at: 2.hours.ago, work_mode: "outside_meeting")
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "outside_meeting", source: "system", attendance_record: rec,
                                 started_at: 2.hours.ago, client: "Acme", title: "Renewal")
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "lunch", source: "employee", ends_at: 20.minutes.from_now)
    create(:attendance_record, user: dev, date: Date.current, check_in_at: 1.hour.ago, work_mode: "office")
    HrLite::WorkModeEvent.start!(user_id: dev.id, mode: "office", source: "system", started_at: 1.hour.ago)
    sign_in admin
  end

  after { travel_back }

  def kpi(label) = response.body[%r{hrl-kpi__value">(\d+)</div>\s*<div class="hrl-kpi__label">(?:(?!</div>).)*#{label}}m, 1].to_i

  it "counts live modes, lists field check-ins and who needs review" do
    get "/hr/admin/work_modes"
    expect(kpi("Outside office meeting")).to eq(1)
    expect(kpi("Lunch break")).to eq(1)
    expect(kpi("In office")).to eq(1)
    expect(kpi("Needs review")).to eq(2) # Ravi and the admin: no check-in
    expect(response.body).to include("Acme").and include("Renewal")
  end

  it "filters the Sales team" do
    get "/hr/admin/work_modes", params: { department: "Sales" }
    expect(kpi("Needs review")).to eq(0)
  end

  it "shows a person's timeline in order with sources" do
    get "/hr/admin/work_modes", params: { user_id: asha.id }
    timeline = response.body[/id="timeline".*/m]
    expect(timeline.index("Outside office meeting")).to be < timeline.index("Lunch break")
    expect(timeline).to include("set automatically").and include("set by the employee")
  end

  it "keeps employees out" do
    sign_in ravi
    get "/hr/admin/work_modes"
    expect(response).to redirect_to("/hr/")
  end

  it "reads a past day from the timeline" do
    travel_to(Time.zone.local(2026, 10, 21, 10, 0))
    get "/hr/admin/work_modes", params: { date: "2026-10-20" }
    expect(kpi("Outside office meeting")).to eq(1)
    expect(kpi("In office")).to eq(1)
  end
end
