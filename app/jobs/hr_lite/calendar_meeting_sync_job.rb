module HrLite
  # Run every few minutes by the host. Asks the host's calendar hook for each
  # connected person's meetings starting soon and schedules Meeting mode for
  # their start. Re-runs are harmless: a meeting opens once per event.
  class CalendarMeetingSyncJob < ApplicationJob
    WINDOW = 10.minutes

    def perform
      hook = HrLite.config.calendar_events
      return unless hook && HrLite.config.calendar_users && HrLite.config.office_geofence

      now = Time.current
      HrLite.user_klass.where(id: HrLite.config.calendar_users.call).find_each do |user|
        meetings(hook, user, now).each do |m|
          next unless m[:id] && m[:starts_at] && m[:ends_at] && m[:ends_at] > now && m[:starts_at] < now + WINDOW

          CalendarMeetingStartJob.set(wait_until: [ m[:starts_at], now ].max)
                                 .perform_later(user.id, m[:id].to_s, m[:title].to_s, m[:ends_at].iso8601)
        end
      end
    end

    private

    # One person's calendar failing (revoked access, Google down) never stops the rest.
    def meetings(hook, user, now)
      Array(hook.call(user, now, now + WINDOW)).map { |m| m.to_h.symbolize_keys }
    rescue => e
      Rails.logger.warn("[hr_lite] calendar sync failed for user #{user.id}: #{e.class}: #{e.message}")
      []
    end
  end
end
