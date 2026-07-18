module HrLite
  # Resolves what each date "is" for a user. This phase knows punches only
  # (present / half_day / absent / upcoming); the leave phase rebuilds it
  # with the full precedence chain (holiday > weekend > leave > punch >
  # absent) — callers depend only on `for(date).kind`.
  class DayStatus
    Day = Struct.new(:kind, :record, keyword_init: true)

    def initialize(user:, range:)
      @range = range
      @records = AttendanceRecord.where(user_id: user.id, date: range).index_by(&:date)
    end

    def for(date)
      record = @records[date]
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
