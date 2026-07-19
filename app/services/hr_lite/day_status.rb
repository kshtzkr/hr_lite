module HrLite
  # Resolves what each date "is" for a user, with the full precedence chain:
  #
  #   holiday > weekend > approved full-day leave > punch > absent/upcoming
  #
  # A half-day leave coexists with a punch (kind :half_day_leave, record
  # exposed); a punch on a holiday keeps :holiday but exposes the record
  # (UI shows a "worked" hint). One resolver feeds the month grids, the
  # overview board and the attendance summary — a single truth.
  class DayStatus
    Day = Struct.new(:kind, :record, :leave, keyword_init: true)

    def initialize(user:, range:)
      @range = range
      @records = AttendanceRecord.where(user_id: user.id, date: range).index_by(&:date)
      @calendar = WorkingCalendar.new(range)
      @leaves = LeaveRequest.approved.includes(:leave_type)
                            .where(user_id: user.id)
                            .overlapping_range(range.first, range.last).to_a
    end

    attr_reader :calendar

    def for(date)
      record = @records[date]
      leave = @leaves.find { |l| l.start_date <= date && l.end_date >= date }

      return Day.new(kind: :holiday, record: record, leave: leave) if @calendar.holiday?(date)
      return Day.new(kind: :weekend, record: record, leave: leave) if @calendar.weekend?(date)

      if leave
        kind = leave.half_day ? :half_day_leave : :leave
        return Day.new(kind: kind, record: record, leave: leave)
      end

      if record&.check_in_at
        Day.new(kind: record.status.to_sym, record: record)
      elsif date > Date.current
        Day.new(kind: :upcoming, record: nil)
      else
        Day.new(kind: :absent, record: record)
      end
    end

    def counts
      @range.each_with_object(Hash.new(0)) { |date, acc| acc[self.for(date).kind] += 1 }
    end
  end
end
