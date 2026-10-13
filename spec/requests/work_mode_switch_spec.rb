require "rails_helper"

RSpec.describe "Switching work modes", type: :request do
  include ActiveJob::TestHelper

  let(:employee) { create(:user, name: "Asha") }
  let(:colleague) { create(:user, name: "Dev") }
  let(:admin) { create(:user, :admin) }
  let(:office) { { lat: "28.6130", lng: "77.36606", accuracy_m: "20", geo_status: "ok" } }

  before do
    HrLite.config.office_geofence = true
    create(:office_location, lat: 28.61270779585808, lng: 77.36605830864376, radius_m: 500)
    travel_to(Time.zone.local(2026, 10, 20, 9, 30))
    sign_in employee
  end

  after { travel_back }

  def check_in = post("/hr/attendance/check_in", params: office)
  def switch(mode, **extra) = post("/hr/work_mode", params: { mode: mode, **extra })
  def status(at: Time.current) = HrLite::WorkStatus.for(employee.id, at: at)

  it "needs a check-in first and never touches the attendance record" do
    switch("busy", minutes: 30)
    expect(flash[:alert]).to include("Check in first")

    check_in
    switch("travelling", destination: "Gurgaon", title: "Vendor visit")
    expect(status.primary).to have_attributes(mode: "travelling", source: "employee")
    expect(HrLite::AttendanceRecord.last.work_mode).to eq("office")
  end

  it "ends lunch on the server at 30 minutes, marks the overrun, and returns to the work mode" do
    check_in
    switch("lunch")
    expect(status.overlay.mode).to eq("lunch")
    travel_to(Time.zone.local(2026, 10, 20, 10, 1))
    perform_enqueued_jobs(only: HrLite::WorkModeExpireJob)
    lunch = HrLite::WorkModeEvent.find_by(mode: "lunch")
    expect(lunch).to have_attributes(end_reason: "expired", overrun: true, ended_at: Time.zone.local(2026, 10, 20, 10, 0))
    expect(status.overlay).to be_nil
    expect(status.primary.mode).to eq("office")
  end

  it "runs the expiry job at the end time, with the browser gone" do
    check_in
    switch("lunch")
    expect(HrLite::WorkModeExpireJob).to have_been_enqueued.at(Time.zone.local(2026, 10, 20, 10, 0))
  end

  it "refuses a second lunch the same day, so the clock can't be reset" do
    check_in
    switch("lunch")
    post "/hr/work_mode/end_overlay"
    switch("lunch")
    expect(flash[:alert]).to include("already taken lunch")
    expect(HrLite::WorkModeEvent.where(mode: "lunch").count).to eq(1)
  end

  it "uses the configured short-break limit and lets busy end at a chosen time" do
    HrLite::Setting.instance.update!(short_break_minutes: 15)
    check_in
    switch("short_break")
    expect(status.overlay.until).to eq(Time.zone.local(2026, 10, 20, 9, 45))

    switch("busy", until: "11:00")
    expect(status.overlay).to have_attributes(mode: "busy", until: Time.zone.local(2026, 10, 20, 11, 0))
    expect(status(at: Time.zone.local(2026, 10, 20, 11, 1)).overlay).to be_nil

    switch("busy", until: "08:00")
    expect(flash[:alert]).to include("later than now")
  end

  it "only allows the WFH mode with WFH approved for today" do
    check_in
    switch("wfh")
    expect(flash[:alert]).to include("approved WFH")
  end

  it "keeps work modes off on a full-day leave" do
    HrLite::WorkModeEvent.start!(user_id: employee.id, mode: "office", source: "system")
    create(:leave_request, :approved, user: employee, start_date: Date.current, end_date: Date.current)
    switch("busy", minutes: 30)
    expect(flash[:alert]).to include("On leave")
  end

  it "lets HR set someone's mode with a reason, never their own, and records the source" do
    sign_in colleague
    post "/hr/admin/work_modes/#{employee.id}", params: { mode: "busy", minutes: 30, reason: "x" }
    expect(HrLite::WorkModeEvent.where(source: "hr")).to be_empty

    sign_in employee
    check_in
    sign_in admin
    post "/hr/admin/work_modes/#{employee.id}", params: { mode: "busy", minutes: 30 }
    expect(flash[:alert]).to include("reason")
    post "/hr/admin/work_modes/#{employee.id}", params: { mode: "busy", minutes: 30, reason: "Covering client call" }
    expect(status.overlay).to have_attributes(mode: "busy", source: "hr")
    expect(HrLite::WorkModeEvent.last.set_by_id).to eq(admin.id)

    post "/hr/admin/work_modes/#{admin.id}", params: { mode: "busy", minutes: 30, reason: "x" }
    expect(response).to have_http_status(:not_found)
  end

  it "shows the current mode with icons, its source, and a countdown on the punch card" do
    check_in
    get "/hr/attendance"
    expect(response.body).to include("In office").and include("set automatically").and include("hrl-mode--auto")
    switch("busy", minutes: 60)
    get "/hr/attendance"
    expect(response.body).to include("hrl-mode--busy").and include("set by the employee").and include("data-hrl-countdown")
      .and include("End busy now")
  end

  it "lets each mode run a picked length, from 15 minutes up to a day, and refuses anything else" do
    check_in
    switch("busy", duration: "15")
    expect(status.overlay.until).to eq(Time.zone.local(2026, 10, 20, 9, 45))
    switch("meeting", title: "Planning", duration: "day")
    expect(status.overlay.until).to eq(Time.zone.local(2026, 10, 21, 9, 30))
    switch("out_of_office", category: "personal", duration: "240")
    expect(status.overlay.until).to eq(Time.zone.local(2026, 10, 20, 13, 30))
    switch("busy", duration: "45")
    expect(flash[:alert]).to include("choices")
  end

  it "runs travelling until changed, or for a picked length" do
    check_in
    switch("travelling", destination: "Gurgaon", title: "Visit", duration: "")
    expect(status.primary.until).to be_nil
    switch("travelling", destination: "Gurgaon", title: "Visit", duration: "120")
    expect(status.primary.until).to eq(Time.zone.local(2026, 10, 20, 11, 30))
  end

  it "keeps breaks within their limit: a shorter lunch is fine, a longer one is refused" do
    check_in
    expect(HrLite::WorkModeSwitch.duration_choices("lunch")).to eq(%w[15 30])
    expect(HrLite::WorkModeSwitch.duration_choices("short_break")).to eq([])
    switch("lunch", duration: "60")
    expect(flash[:alert]).to include("30-minute limit")
    switch("lunch", duration: "15")
    expect(status.overlay.until).to eq(Time.zone.local(2026, 10, 20, 9, 45))
  end

  it "offers the lengths as chips in each form" do
    check_in
    get "/hr/attendance"
    expect(response.body).to include('name="duration" id="dur-busy-15" value="15"').and include("1 day").and include("Until I change it")
    expect(response.body).to include('id="dur-lunch-30"')
    expect(response.body).not_to include('id="dur-lunch-60"')
  end
end
