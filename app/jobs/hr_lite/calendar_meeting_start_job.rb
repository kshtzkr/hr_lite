module HrLite
  # Opens Meeting mode (system-set) for a calendar event at its start, until
  # its end, for someone checked in. It never overrides a break or a mode the
  # person or HR chose, and never runs on leave or a holiday.
  class CalendarMeetingStartJob < ApplicationJob
    def perform(user_id, calendar_event_id, title, ends_at)
      ends_at = Time.zone.parse(ends_at)
      return if ends_at <= Time.current || WorkModeEvent.exists?(user_id: user_id, calendar_event_id: calendar_event_id)

      record = AttendanceRecord.find_by(user_id: user_id, date: Time.current.in_time_zone(HrLite.config.time_zone).to_date)
      return unless record&.check_in_at && record.check_out_at.nil?

      status = WorkStatus.for(user_id)
      return unless status.primary.event
      return if status.overlay && status.overlay.source != "system"

      event = WorkModeEvent.start!(user_id: user_id, mode: "meeting", source: "system", title: title.truncate(120).presence || "Calendar meeting",
                                   ends_at: ends_at, calendar_event_id: calendar_event_id, attendance_record: record)
      WorkModeExpireJob.set(wait_until: ends_at).perform_later(event.id)
    rescue ActiveRecord::RecordNotUnique
      nil # another run opened it first
    end
  end
end
