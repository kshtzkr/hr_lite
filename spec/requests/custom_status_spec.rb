require "rails_helper"

RSpec.describe "Custom status", type: :request do
  include ActiveJob::TestHelper

  let(:asha) { create(:user, name: "Asha") }
  let(:ravi) { create(:user, name: "Ravi") }
  let(:now) { Time.zone.local(2026, 10, 20, 11, 0) }

  before do
    HrLite.config.office_geofence = true
    travel_to(now)
    sign_in asha
  end

  after { travel_back }

  def status = HrLite::WorkStatus.for(asha.id)

  it "sets a status with an emoji without checking in, and teammates see it" do
    post "/hr/work_mode/status", params: { emoji: "🏔️", text: "At the Ladakh camp", clear_after: "never" }
    expect(status.custom).to have_attributes(emoji: "🏔️", title: "At the Ladakh camp", ends_at: nil)

    sign_in ravi
    get "/hr/team"
    expect(response.body).to include("🏔️").and include("At the Ladakh camp")
  end

  it "clears itself on the chosen timer, on the server" do
    post "/hr/work_mode/status", params: { text: "Dentist", clear_after: "60" }
    expect(HrLite::WorkModeExpireJob).to have_been_enqueued.at(now + 1.hour)
    travel_to(now + 61.minutes)
    perform_enqueued_jobs(only: HrLite::WorkModeExpireJob)
    expect(status.custom).to be_nil
  end

  it "refuses words in the emoji field and an empty status" do
    post "/hr/work_mode/status", params: { emoji: "hi", text: "x" }
    expect(flash[:alert]).to include("single emoji")
    post "/hr/work_mode/status", params: { clear_after: "today" }
    expect(flash[:alert]).to include("Write a status")
  end

  it "survives check-out and the nightly close, and stays out of work-time totals" do
    post "/hr/work_mode/status", params: { emoji: "🌴", clear_after: "never" }
    record = create(:attendance_record, user: asha, date: Date.current, check_in_at: now - 2.hours)
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "office", source: "system", attendance_record: record, at: now - 2.hours)
    HrLite::WorkModeEvent.close_all!(asha.id, "checked_out")
    travel_to(now.end_of_day - 5.minutes)
    HrLite::AttendanceCloseJob.perform_now(date: Date.current)
    expect(status.custom&.emoji).to eq("🌴")

    result = HrLite::WorkModeDurations.call([ asha.id ], HrLite::WorkModeDurations::Period.build("day", Date.current))
    expect(result.by_mode.keys).not_to include("custom")
  end

  it "replaces the previous status and keeps it in history; clear ends it" do
    post "/hr/work_mode/status", params: { text: "One", clear_after: "never" }
    post "/hr/work_mode/status", params: { text: "Two", clear_after: "never" }
    expect(HrLite::WorkModeEvent.where(mode: "custom").order(:id).pluck(:title, :end_reason)).to eq([ [ "One", "switched" ], [ "Two", nil ] ])
    post "/hr/work_mode/clear_status"
    expect(status.custom).to be_nil
  end
end
