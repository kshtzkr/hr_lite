module HrLite
  # Month roll-up per user — the payroll contract. Exact math per date:
  #
  #   holiday / weekend / present / paid full-day leave  -> payable +1
  #   unpaid full-day leave (LWP) / absent               -> lop +1
  #   half-day punch (no leave)                          -> payable +0.5, lop +0.5
  #   half-day PAID leave: leave half payable; other half payable if
  #     punched, else lop (unpaid half-day leave: leave half is lop too)
  #   future dates                                       -> upcoming (neither)
  #
  # For closed months: payable + lop + upcoming == days_in_month.
  module AttendanceSummary
    def self.for(user:, month:)
      range = month.beginning_of_month..month.end_of_month
      from_day_status(DayStatus.new(user: user, range: range), range)
    end

    # Batch variant for team/payroll screens: 3 queries total, not 3×N.
    def self.for_all(users:, month:)
      users.index_with { |user| self.for(user: user, month: month) }.transform_keys(&:id)
    end

    def self.from_day_status(day_status, range)
      summary = {
        present: 0.to_d, half_day: 0.to_d, paid_leave: 0.to_d, unpaid_leave: 0.to_d,
        holiday: 0, weekend: 0, absent: 0.to_d, upcoming: 0,
        payable_days: 0.to_d, lop_days: 0.to_d, days_in_month: range.count
      }

      range.each do |date|
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
          if day.leave.paid?
            summary[:paid_leave] += 1
            summary[:payable_days] += 1
          else
            summary[:unpaid_leave] += 1
            summary[:lop_days] += 1
          end
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

      if day.leave.paid?
        summary[:paid_leave] += half
        summary[:payable_days] += half
      else
        summary[:unpaid_leave] += half
        summary[:lop_days] += half
      end

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
