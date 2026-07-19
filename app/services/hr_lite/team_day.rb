module HrLite
  # One row per staff member for a single date — powers the everyone-visible
  # Team board: who's in, who's out, who's on leave, hours worked. Batch
  # queries (five total, regardless of team size); the per-day precedence
  # mirrors DayStatus (holiday > weekend > leave > punch > absent/upcoming).
  class TeamDay
    Row = Struct.new(:user, :profile, :kind, :record, :leave,
                     :day_seconds, :month_seconds, :date, keyword_init: true) do
      def date_today?
        date == Date.current
      end
    end

    def initialize(date: Date.current)
      @date = date
      @calendar = WorkingCalendar.new(date..date)
    end

    attr_reader :date, :calendar

    def rows
      @rows ||= build_rows
    end

    def kpis
      {
        checked_in: rows.count { |r| r.record&.check_in_at },
        on_leave: rows.count { |r| %i[leave half_day_leave].include?(r.kind) },
        not_in: rows.count { |r| r.kind == :absent }
      }
    end

    private

    def build_rows
      users = HrLite.employees
      ids = users.map(&:id)
      profiles = EmployeeProfile.where(user_id: ids).index_by(&:user_id)
      records = AttendanceRecord.for_date(@date).where(user_id: ids).index_by(&:user_id)
      leaves = LeaveRequest.active_on(@date).includes(:leave_type)
                           .where(user_id: ids).index_by(&:user_id)
      month_records = AttendanceRecord.for_month(@date).where(user_id: ids).group_by(&:user_id)

      users.filter_map do |user|
        profile = profiles[user.id]
        next if profile && !profile.active_on?(@date)

        record = records[user.id]
        leave = leaves[user.id]
        Row.new(
          user: user, profile: profile,
          kind: kind_for(record, leave),
          record: record, leave: leave,
          day_seconds: seconds_worked(record),
          month_seconds: (month_records[user.id] || []).sum { |r| seconds_worked(r) || 0 },
          date: @date
        )
      end
    end

    def kind_for(record, leave)
      return :holiday if @calendar.holiday?(@date)
      return :weekend if @calendar.weekend?(@date)
      return (leave.half_day ? :half_day_leave : :leave) if leave

      if record&.check_in_at
        record.status.to_sym
      elsif @date > Date.current
        :upcoming
      else
        :absent
      end
    end

    # Finished punch → actual duration; still checked in today → running
    # clock, so the board answers "how long have they been in so far".
    def seconds_worked(record)
      return nil unless record&.check_in_at
      return record.worked_duration if record.check_out_at

      record.date == Date.current ? Time.current - record.check_in_at : nil
    end
  end
end
