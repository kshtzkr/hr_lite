module HrLite
  # Hybrid balance: only carry-in and manual adjustments are stored;
  # entitlement accrues as a pure function of the policy and `used` is
  # recomputed live from approved requests — so a holiday added after an
  # approval self-heals both the quota and payroll.
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

      quota = leave_type.annual_quota
      base =
        if leave_type.accrual == "monthly"
          months = as_of.year == year ? as_of.month : (as_of.year > year ? 12 : 0)
          ((quota / 12) * months).round(1)
        else
          quota
        end
      base + carried_forward + adjustment
    end

    def used
      requests = LeaveRequest.approved
                             .where(user_id: user_id, leave_type_id: leave_type_id)
                             .where(start_date: Date.new(year, 1, 1)..Date.new(year, 12, 31))
      requests.sum { |request| LeaveDayCounter.count(request) }
    end

    def available(as_of: Date.current)
      entitled(as_of: as_of) - used
    end
  end
end
