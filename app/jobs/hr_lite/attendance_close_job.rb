module HrLite
  # Closes the working day; the host schedules it at 23:55. A punch left open
  # is checked out and paid as a half day. Nobody punched in already reads as
  # absent (DayStatus), so they are only told. Leave days are left alone.
  class AttendanceCloseJob < ApplicationJob
    def perform(date: Date.current)
      return unless WorkingCalendar.new(date..date).working_day?(date)

      on_leave = LeaveRequest.active_on(date).pluck(:user_id)
      records = AttendanceRecord.for_date(date).index_by(&:user_id)
      day = date.strftime("%d %b")
      HrLite.active_employees(on: date).each do |user|
        next if on_leave.include?(user.id)

        record = records[user.id]
        if record.nil? || record.check_in_at.nil?
          tell(user, date, "attendance.missed_check_in", "You didn't check in on #{day} — marked absent")
        elsif record.check_out_at.nil?
          record.update!(check_out_at: Time.current, status: "half_day",
                         regularization_note: AttendanceRecord::AUTO_CHECKOUT_NOTE)
          tell(user, date, "attendance.missed_check_out", "You didn't check out on #{day} — marked half day")
        end
      end
    end

    private

    def tell(user, date, event, title)
      rule = HrLite.config.self_regularization
      body = if rule
        "Fix it yourself by #{(date + rule[:within_days]).strftime('%d %b')} (up to #{rule[:per_week]} a week), " \
          "or raise a ticket for HR."
      else
        "Raise a regularization ticket to get it fixed."
      end
      Notifications.publish(event, title: title, body: body, path: "/regularization_requests/new?date=#{date.iso8601}",
                                   bell_to: [ user ], email_to: [ user ])
    end
  end
end
