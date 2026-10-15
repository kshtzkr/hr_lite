module HrLite
  # Closes the working day that ended last: a run at 23:55 closes today, and a
  # retry or late run after midnight (or a morning schedule) closes yesterday.
  # A punch left open is checked out at the day's end and paid as a half day,
  # and so is a closed punch under the half-day line HR sets in Settings.
  # Nobody punched in already reads as absent (DayStatus), so they are only
  # told. Leave days, and each person's weekends and office holidays, are left alone.
  class AttendanceCloseJob < ApplicationJob
    def perform(date: (Time.current - 12.hours).to_date)
      calendars = WorkingCalendar.by_office(date..date)
      offices = EmployeeProfile.pluck(:user_id, :office_location_id).to_h
      on_leave = LeaveRequest.active_on(date).pluck(:user_id)
      records = AttendanceRecord.for_date(date).index_by(&:user_id)
      day = date.strftime("%d %b")
      HrLite.active_employees(on: date).each do |user|
        next if on_leave.include?(user.id) || !calendars[offices[user.id]].working_day?(date)

        record = records[user.id]
        if record.nil? || record.check_in_at.nil?
          tell(user, date, "attendance.missed_check_in", "You didn't check in on #{day} — marked absent")
        elsif record.check_out_at.nil?
          record.update!(check_out_at: date.end_of_day, status: "half_day",
                         regularization_note: AttendanceRecord::AUTO_CHECKOUT_NOTE)
          tell(user, date, "attendance.missed_check_out", "You didn't check out on #{day} — marked half day")
        elsif !record.regularized? && record.status == "present" && record.below_half_day?
          record.update!(status: "half_day", regularization_note: AttendanceRecord::SHORT_DAY_NOTE)
          line = Setting.instance.half_day_below_minutes
          tell(user, date, "attendance.short_day",
               "You worked #{(record.worked_duration / 3600.0).round(1)}h on #{day}, under #{line / 60}h#{format('%02d', line % 60)} — marked half day")
        end
        penalize_short_day(record) if record&.check_out_at
      end
      close_work_modes(date) if HrLite.config.office_geofence
    end

    private

    # Anything still running from that day ends at its close; Offline stays open.
    def close_work_modes(date)
      day_end = [ date.in_time_zone(HrLite.config.time_zone).end_of_day, Time.current ].min
      WorkModeEvent.open.work.where.not(mode: "offline").where(started_at: ..day_end).find_each { |e| e.close!("day_closed", at: day_end) }
    end

    # Out before the slot's required checkout: +30 min on the next working day.
    def penalize_short_day(record)
      return unless HrLite.config.attendance_slots && record.check_out_at < record.required_check_out_at

      next_day = AttendancePenalty.next_working_days(record.user_id, record.date, 1).first
      AttendancePenalty.find_or_create_by!(attendance_record: record, reason: "short_day", date: next_day) do |p|
        p.user_id = record.user_id
        p.minutes = AttendanceSlot::STEP_MINUTES
      end
    end

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
