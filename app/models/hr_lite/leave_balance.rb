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

    def entitled(as_of: Date.current)
      return Float::INFINITY if leave_type.unlimited?

      (accrued_base(as_of) + carried_forward + adjustment).round(1)
    end

    def used
      range = LeaveYear.range(year)
      requests = LeaveRequest.approved
                             .where(user_id: user_id, leave_type_id: leave_type_id)
                             .where(start_date: range)
      requests.sum { |request| LeaveDayCounter.count(request) }
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
      return 0 if start.nil?

      monthly_rate = leave_type.annual_quota / 12
      months =
        if leave_type.accrual == "monthly"
          cap = [ as_of, range.last ].min
          start > cap ? 0 : months_between(start, cap)
        else
          months_between(start, range.last)
        end
      monthly_rate * months
    end

    # nil when the person joins only after this leave year ends.
    def accrual_start(range)
      doj = EmployeeProfile.where(user_id: user_id).pick(:date_of_joining)
      return range.first if doj.nil? || doj <= range.first

      start = doj.day <= 15 ? doj.beginning_of_month : doj.next_month.beginning_of_month
      start > range.last ? nil : start
    end

    def months_between(from, to)
      (to.year * 12 + to.month) - (from.year * 12 + from.month) + 1
    end
  end
end
