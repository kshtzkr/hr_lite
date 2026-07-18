module HrLite
  # How many working days a leave request actually consumes. Weekends and
  # company-wide holidays inside the range are free; a half-day (single-day
  # requests only) consumes 0.5.
  module LeaveDayCounter
    def self.count(leave_request)
      count_range(
        start_date: leave_request.start_date,
        end_date: leave_request.end_date,
        half_day: leave_request.half_day
      )
    end

    def self.count_range(start_date:, end_date:, half_day: false)
      return 0 if start_date.nil? || end_date.nil? || end_date < start_date

      range = start_date..end_date
      working = WorkingCalendar.new(range).working_days_in(range)
      return BigDecimal("0.5") if half_day && working.positive?

      BigDecimal(working)
    end
  end
end
