module HrLite
  # Month roll-up per user — the payroll contract. Exact math per date:
  #
  #   holiday / weekend / present / paid full-day leave  -> payable +1
  #   unpaid full-day leave (LWP, or a paid-type day beyond the balance —
  #     LeaveRequest#unpaid_on) / absent                 -> lop +1
  #   half-day punch (no leave)                          -> payable +0.5, lop +0.5
  #   half-day PAID leave: leave half payable; other half payable if
  #     punched, else lop (unpaid half-day leave: leave half is lop too)
  #   future dates                                       -> upcoming (neither)
  #   dates outside the employment window (before DOJ / after exit, when an
  #     EmployeeProfile exists)                          -> out_of_window (neither)
  #
  # The window lives HERE and only here — payroll consumes payable/lop as-is
  # and never re-clips, so a mid-month joiner is never double-penalized.
  # For closed months: payable + lop + upcoming + out_of_window == days_in_month.
  module AttendanceSummary
    def self.for(user:, month:)
      range = month.beginning_of_month..month.end_of_month
      profile = EmployeeProfile.find_by(user_id: user.id)
      from_day_status(DayStatus.new(user: user, range: range), range, profile: profile)
    end

    # Batch variant for team/payroll screens: 3 queries total, not 3×N.
    def self.for_all(users:, month:)
      users.index_with { |user| self.for(user: user, month: month) }.transform_keys(&:id)
    end

    def self.from_day_status(day_status, range, profile: nil)
      summary = {
        present: 0.to_d, half_day: 0.to_d, paid_leave: 0.to_d, unpaid_leave: 0.to_d,
        holiday: 0, weekend: 0, absent: 0.to_d, upcoming: 0, out_of_window: 0,
        payable_days: 0.to_d, lop_days: 0.to_d, days_in_month: range.count
      }

      range.each do |date|
        if profile && !profile.active_on?(date)
          summary[:out_of_window] += 1
          next
        end

        day = day_status.for(date)
        case day.kind
        when :holiday
          summary[:holiday] += 1
          summary[:payable_days] += 1
        when :weekend
          summary[:weekend] += 1
          summary[:payable_days] += 1
        when :present
          summary[:present] += 1
          summary[:payable_days] += 1
        when :half_day
          summary[:half_day] += 1
          summary[:payable_days] += BigDecimal("0.5")
          summary[:lop_days] += BigDecimal("0.5")
        when :leave
          unpaid = day.leave.paid? ? day.leave.unpaid_on(date) : 1
          summary[:paid_leave] += 1 - unpaid
          summary[:payable_days] += 1 - unpaid
          summary[:unpaid_leave] += unpaid
          summary[:lop_days] += unpaid
        when :half_day_leave
          apply_half_day_leave(summary, day)
        when :upcoming
          summary[:upcoming] += 1
        else # :absent
          summary[:absent] += 1
          summary[:lop_days] += 1
        end
      end

      summary
    end

    def self.apply_half_day_leave(summary, day)
      half = BigDecimal("0.5")

      unpaid = day.leave.paid? ? day.leave.unpaid_on(day.leave.start_date) : half
      summary[:paid_leave] += half - unpaid
      summary[:payable_days] += half - unpaid
      summary[:unpaid_leave] += unpaid
      summary[:lop_days] += unpaid

      if day.record&.check_in_at
        summary[:present] += half
        summary[:payable_days] += half
      else
        summary[:absent] += half
        summary[:lop_days] += half
      end
    end
    private_class_method :apply_half_day_leave
  end
end
