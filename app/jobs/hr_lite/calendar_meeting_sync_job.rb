module HrLite
  # Keeps Meeting mode in step with each person's calendar. The host runs it
  # for everyone every few minutes, and for one person the moment Google says
  # their calendar changed. Each run schedules meetings starting soon and
  # reconciles open ones: a cancelled or declined invite ends the meeting, a
  # moved end time moves it. Re-runs are harmless.
  class CalendarMeetingSyncJob < ApplicationJob
    WINDOW = 10.minutes

    def perform(user_ids = nil)
      hook = HrLite.config.calendar_events
      return unless hook && HrLite.config.calendar_users && HrLite.config.office_geofence

      now = Time.current
      ids = HrLite.config.calendar_users.call
      ids &= Array(user_ids).map(&:to_i) if user_ids
      HrLite.user_klass.where(id: ids).find_each do |user|
        meetings = self.class.meetings(hook, user, now, now + WINDOW)
        next if meetings.nil? # the calendar could not be read: leave everything as it is

        reconcile(user, meetings, now)
        meetings.each do |m|
          next unless m[:starts_at] < now + WINDOW && m[:ends_at] > now

          CalendarMeetingStartJob.set(wait_until: [ m[:starts_at], now ].max).perform_later(user.id, m[:id])
        end
      end
    end

    # Timed meetings overlapping from..to, or nil when the hook fails.
    def self.meetings(hook, user, from, to)
      Array(hook.call(user, from, to)).map { |m| m.to_h.symbolize_keys }
                                      .select { |m| m[:id].present? && m[:starts_at] && m[:ends_at] }
                                      .each { |m| m[:id] = m[:id].to_s }
    rescue => e
      HrLite.record_failure("calendar_read", e, subject: user)
      nil
    end

    private

    def reconcile(user, meetings, now)
      by_id = meetings.index_by { |m| m[:id] }
      WorkModeEvent.open.where(user_id: user.id, source: "system").where.not(calendar_event_id: nil).find_each do |event|
        meeting = by_id[event.calendar_event_id]
        if meeting.nil? || meeting[:starts_at] > now
          event.close!("ended", at: now) # cancelled, declined or moved later
        elsif meeting[:ends_at] != event.ends_at && meeting[:ends_at] > now
          event.update!(ends_at: meeting[:ends_at])
          WorkModeExpireJob.set(wait_until: meeting[:ends_at]).perform_later(event.id)
        end
      end
    end
  end
end
