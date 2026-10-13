require "rails_helper"

RSpec.describe "Calendar meetings" do
  include ActiveJob::TestHelper

  let(:asha) { create(:user, name: "Asha") }
  let(:now) { Time.zone.local(2026, 10, 20, 10, 55) }
  let(:meeting) { { id: "evt-1", title: "Weekly sync", starts_at: now + 5.minutes, ends_at: now + 35.minutes } }

  before do
    HrLite.config.office_geofence = true
    HrLite.config.calendar_users = -> { [ asha.id ] }
    HrLite.config.calendar_events = ->(_user, _from, _to) { [ meeting ] }
    travel_to(now)
    record = create(:attendance_record, user: asha, date: now.to_date, check_in_at: now - 2.hours)
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "office", source: "system", attendance_record: record, at: now - 2.hours)
  end

  after { travel_back }

  def status = HrLite::WorkStatus.for(asha.id)

  it "schedules the meeting for its start, opens it then, and ends it with the event" do
    HrLite::CalendarMeetingSyncJob.perform_now
    expect(HrLite::CalendarMeetingStartJob).to have_been_enqueued.at(now + 5.minutes)

    travel_to(now + 5.minutes)
    perform_enqueued_jobs(only: HrLite::CalendarMeetingStartJob)
    expect(status.overlay).to have_attributes(mode: "meeting", source: "system", until: now + 35.minutes)

    travel_to(now + 36.minutes)
    perform_enqueued_jobs(only: HrLite::WorkModeExpireJob)
    expect(status.overlay).to be_nil
    expect(status.primary.mode).to eq("office")
  end

  it "opens one meeting however many syncs see the event" do
    2.times { HrLite::CalendarMeetingStartJob.perform_now(asha.id, "evt-1", "Weekly sync", (now + 35.minutes).iso8601) }
    expect(HrLite::WorkModeEvent.where(calendar_event_id: "evt-1").count).to eq(1)
  end

  it "never overrides a break or a mode the person chose" do
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "lunch", source: "employee", ends_at: now + 30.minutes)
    HrLite::CalendarMeetingStartJob.perform_now(asha.id, "evt-1", "Weekly sync", (now + 35.minutes).iso8601)
    expect(status.overlay.mode).to eq("lunch")
  end

  it "does nothing for someone not checked in" do
    HrLite::AttendanceRecord.update_all(check_out_at: now)
    HrLite::CalendarMeetingStartJob.perform_now(asha.id, "evt-1", "Weekly sync", (now + 35.minutes).iso8601)
    expect(HrLite::WorkModeEvent.where(mode: "meeting")).to be_empty
  end

  it "keeps going when one calendar fails, and is off without the hooks" do
    HrLite.config.calendar_events = ->(_u, _f, _t) { raise "revoked" }
    expect { HrLite::CalendarMeetingSyncJob.perform_now }.not_to raise_error
    HrLite.config.calendar_events = nil
    HrLite::CalendarMeetingSyncJob.perform_now
    expect(HrLite::CalendarMeetingStartJob).not_to have_been_enqueued
  end
end
