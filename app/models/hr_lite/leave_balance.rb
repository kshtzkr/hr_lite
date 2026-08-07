module HrLite
  # Hybrid balance: only carry-in and manual adjustments are stored;
  # entitlement accrues as a pure function of the policy and `used` is
  # recomputed live from approved requests — so a holiday added after an
  # approval self-heals both the quota and payroll.
  #
  # `year` is a LeaveYear key (calendar year by default; with
  # config.leave_year_start_month = 7, key 2026 = Jul 2026 – Jun 2027).
  # Entitlement prorates from the joining date, Keka-style: joined on or
  # before the 15th → that month counts; after the 15th → from next month.
  class LeaveBalance < ApplicationRecord
    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :leave_type

    validates :year, presence: true,
                     uniqueness: { scope: %i[user_id leave_type_id] }

    def self.for(user, leave_type, year)
      find_or_initialize_by(user_id: user.id, leave_type: leave_type, year: year)
    end

    # Persisted and row-locked so concurrent writers serialize here. The
    # create sits in its own savepoint: on PostgreSQL a failed INSERT aborts
    # the enclosing transaction, so a plain rescue could never run.
    def self.lock_for(user, leave_type, year)
      attributes = { user_id: user.id, leave_type_id: leave_type.id, year: year }
      balance = find_by(attributes)
      balance ||= begin
        transaction(requires_new: true) { create!(attributes) }
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        find_by!(attributes)
      end
      balance.lock!
      balance
    end

    # The single write path for the stored adjustment. Both callers — the
    # comp-off credit and the admin correction — increment the same column,
    # and read-modify-write without the lock lost one of them.
    def self.adjust!(user, leave_type, year, delta:, note:)
      transaction do
        balance = lock_for(user, leave_type, year)
        balance.adjustment += delta
        balance.adjustment_note = [ balance.adjustment_note.presence, note ].compact.join("; ")
        balance.save!
        balance
      end
    end

    def entitled(as_of: Date.current)
      return Float::INFINITY if leave_type.unlimited?

      (accrued_base(as_of) + carried_forward + adjustment).round(1)
    end

    def used
      range = LeaveYear.range(year)
      requests = LeaveRequest.approved
                             .where(user_id: user_id, leave_type_id: leave_type_id)
                             .where(start_date: range)
      # ONE calendar for the whole leave year, reused across every request.
      # Building one per request meant a Holiday query and a Setting query
      # each — and the admin balances grid reads this cell for every employee
      # times every leave type.
      calendar = WorkingCalendar.new(range)
      requests.sum { |request| LeaveDayCounter.count(request, calendar: calendar) }
    end

    def available(as_of: Date.current)
      entitled(as_of: as_of) - used
    end

    private

    # Quota earned by as_of, before carry/adjustments. Monthly accrual
    # drips quota/12 per month from the accrual start (leave-year start,
    # or the prorated joining month for mid-year joiners); yearly_upfront
    # grants all months from the accrual start to the year's end at once.
    def accrued_base(as_of)
      range = LeaveYear.range(year)
      start = accrual_start(range)
      finish = accrual_end(range)
      return 0 if start.nil? || start > finish

      monthly_rate = leave_type.annual_quota / 12
      months =
        if leave_type.accrual == "monthly"
          cap = [ as_of, finish ].min
          start > cap ? 0 : months_between(start, cap)
        else
          months_between(start, finish)
        end
      monthly_rate * months
    end

    # nil when the person joins only after this leave year ends.
    def accrual_start(range)
      doj = employment_window.first
      return range.first if doj.nil? || doj <= range.first

      start = doj.day <= 15 ? doj.beginning_of_month : doj.next_month.beginning_of_month
      start > range.last ? nil : start
    end

    # Quota stops accruing on the last working day — entitlement used to keep
    # growing for months after someone had left.
    def accrual_end(range)
      exit_date = employment_window.last
      exit_date ? [ exit_date, range.last ].min : range.last
    end

    def employment_window
      @employment_window ||= EmployeeProfile.where(user_id: user_id)
                                            .pick(:date_of_joining, :date_of_exit) || [ nil, nil ]
    end

    def months_between(from, to)
      (to.year * 12 + to.month) - (from.year * 12 + from.month) + 1
    end
  end
end
