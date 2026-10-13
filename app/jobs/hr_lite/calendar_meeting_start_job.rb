module HrLite
  # Opens Meeting mode (system-set) for a calendar event at its start. It asks
  # the calendar again first, so a meeting moved or cancelled since it was
  # scheduled does not open. It never overrides a break or a mode the person
  # or HR chose, and only runs for someone checked in.
  class CalendarMeetingStartJob < ApplicationJob
    def perform(user_id, calendar_event_id)
      now = Time.current
      return if WorkModeEvent.exists?(user_id: user_id, calendar_event_id: calendar_event_id)

      user = HrLite.user_klass.find_by(id: user_id) or return
      hook = HrLite.config.calendar_events or return
      meeting = CalendarMeetingSyncJob.meetings(hook, user, now, now + 1.minute)&.find { |m| m[:id] == calendar_event_id }
      return unless meeting && meeting[:starts_at] <= now + 1.minute && meeting[:ends_at] > now

      record = AttendanceRecord.find_by(user_id: user_id, date: now.in_time_zone(HrLite.config.time_zone).to_date)
      return unless record&.check_in_at && record.check_out_at.nil?

      status = WorkStatus.for(user_id)
      return unless status.primary.event
      return if status.overlay && status.overlay.source != "system"

      event = WorkModeEvent.start!(user_id: user_id, mode: "meeting", source: "system", at: now, ends_at: meeting[:ends_at],
                                   title: meeting[:title].to_s.truncate(120).presence || "Calendar meeting",
                                   calendar_event_id: calendar_event_id, attendance_record: record)
      WorkModeExpireJob.set(wait_until: meeting[:ends_at]).perform_later(event.id)
    rescue ActiveRecord::RecordNotUnique
      nil # another run opened it first
    end
  end
end
