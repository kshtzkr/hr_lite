module HrLite
  # Ends a timed mode at its end time on the server, browser or not. A break
  # the system had to end at its limit is marked as an overrun for HR.
  class WorkModeExpireJob < ApplicationJob
    def perform(event_id)
      event = WorkModeEvent.open.find_by(id: event_id)
      return unless event&.ends_at && event.ends_at <= Time.current

      event.update!(ended_at: event.ends_at, end_reason: "expired", overrun: %w[lunch short_break].include?(event.mode))
    end
  end
end
