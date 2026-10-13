module HrLite
  # Who is in today and whether on time, for the Home card. "On time" uses
  # each person's own slot plus their HR buffer and the grace minutes — the
  # same rule as the late penalty. Leave, holidays and weekends are left out.
  class TodayCheckins
    Person = Struct.new(:user, :record, :late_minutes, keyword_init: true) do
      def late? = late_minutes.to_i.positive?
    end

    def initialize(board = TeamDay.new(date: Date.current), now: Time.current)
      @board = board
      @now = now
    end

    def groups
      @groups ||= begin
        rows = @board.rows.reject { |r| %i[holiday weekend leave].include?(r.kind) }
        ids = rows.map { |r| r.user.id }
        starts = AttendanceSlot.where(user_id: ids).overlapping(@board.date, @board.date).order(:created_at)
                               .each_with_object({}) { |s, h| h[s.user_id] = s.start_minute }
        buffers = EmployeeProfile.where(user_id: ids).pluck(:user_id, :buffer_minutes).to_h
        people = rows.map do |r|
          Person.new(user: r.user, record: r.record&.check_in_at ? r.record : nil,
                     late_minutes: late(r.record, starts[r.user.id], buffers[r.user.id]))
        end
        in_now, not_in = people.partition(&:record)
        { on_time: in_now.reject(&:late?), late: in_now.select(&:late?), not_in: not_in }
      end
    end

    private

    def late(record, start, buffer)
      return 0 unless record&.check_in_at

      local = record.check_in_at.in_time_zone(HrLite.config.time_zone)
      over = local.hour * 60 + local.min - (start || AttendanceSlot::DEFAULT_START_MINUTE) - buffer.to_i
      over > AttendanceSlot::GRACE_MINUTES ? over : 0
    end
  end
end
