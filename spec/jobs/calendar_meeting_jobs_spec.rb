require "rails_helper"

RSpec.describe "Calendar meetings" do
  include ActiveJob::TestHelper

  let(:asha) { create(:user, name: "Asha") }
  let(:now) { Time.zone.local(2026, 10, 20, 10, 55) }
  let(:calendar) { [ { id: "evt-1", title: "Weekly sync", starts_at: now + 5.minutes, ends_at: now + 35.minutes } ] }

  before do
    HrLite.config.office_geofence = true
    HrLite.config.calendar_users = -> { [ asha.id ] }
    HrLite.config.calendar_events = ->(_user, from, to) { calendar.select { |m| m[:starts_at] < to && m[:ends_at] > from } }
    travel_to(now)
    record = create(:attendance_record, user: asha, date: now.to_date, check_in_at: now - 2.hours)
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "office", source: "system", attendance_record: record, at: now - 2.hours)
  end

  after { travel_back }

  def status = HrLite::WorkStatus.for(asha.id)

  def start_meeting
    HrLite::CalendarMeetingSyncJob.perform_now
    travel_to(now + 5.minutes)
    perform_enqueued_jobs(only: HrLite::CalendarMeetingStartJob)
  end

  it "schedules the meeting, opens it at its start and ends it with the event" do
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

  it "syncs one person on demand (a push from the calendar)" do
    HrLite::CalendarMeetingSyncJob.perform_now([ asha.id ])
    expect(HrLite::CalendarMeetingStartJob).to have_been_enqueued
    clear_enqueued_jobs
    HrLite::CalendarMeetingSyncJob.perform_now([ 0 ])
    expect(HrLite::CalendarMeetingStartJob).not_to have_been_enqueued
  end

  it "does not open a meeting moved later after it was scheduled" do
    HrLite::CalendarMeetingSyncJob.perform_now
    calendar.first.merge!(starts_at: now + 1.hour, ends_at: now + 2.hours)
    travel_to(now + 5.minutes)
    perform_enqueued_jobs(only: HrLite::CalendarMeetingStartJob)
    expect(status.overlay).to be_nil
  end

  it "ends a meeting when the invite is cancelled, and follows a moved end time" do
    start_meeting
    calendar.first[:ends_at] = now + 50.minutes
    HrLite::CalendarMeetingSyncJob.perform_now
    expect(status.overlay.until).to eq(now + 50.minutes)

    calendar.clear
    HrLite::CalendarMeetingSyncJob.perform_now
    expect(status.overlay).to be_nil
    expect(HrLite::WorkModeEvent.find_by(calendar_event_id: "evt-1").end_reason).to eq("ended")
  end

  it "opens one meeting however often it syncs" do
    start_meeting
    2.times { HrLite::CalendarMeetingStartJob.perform_now(asha.id, "evt-1") }
    expect(HrLite::WorkModeEvent.where(calendar_event_id: "evt-1").count).to eq(1)
  end

  it "never overrides a break or a mode the person chose, nor runs when checked out" do
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "lunch", source: "employee", ends_at: now + 30.minutes)
    start_meeting
    expect(status.overlay.mode).to eq("lunch")

    HrLite::AttendanceRecord.update_all(check_out_at: now)
    HrLite::WorkModeEvent.where(mode: "lunch").update_all(ended_at: now + 5.minutes)
    HrLite::CalendarMeetingStartJob.perform_now(asha.id, "evt-1")
    expect(HrLite::WorkModeEvent.where(mode: "meeting")).to be_empty
  end

  it "leaves meetings alone when the calendar can't be read, and is off without the hooks" do
    start_meeting
    HrLite.config.calendar_events = ->(_u, _f, _t) { raise "revoked" }
    expect { HrLite::CalendarMeetingSyncJob.perform_now }.not_to raise_error
    expect(status.overlay.mode).to eq("meeting")
    expect(HrLite::AuditLog.find_by(action: "failure.calendar_read").subject_id).to eq(asha.id)

    HrLite.config.calendar_events = nil
    clear_enqueued_jobs
    HrLite::CalendarMeetingSyncJob.perform_now
    expect(HrLite::CalendarMeetingStartJob).not_to have_been_enqueued
  end
end
