module HrLite
  # Jan-1 rollover: materialize carry-forward into the new year's balance
  # rows. Idempotent — a balance whose carry has already been written is
  # never touched again (manual adjustments stay safe).
  class LeaveYearRolloverJob < ActiveJob::Base
    queue_as :default

    def perform(year: Date.current.year)
      previous_year = year - 1

      LeaveType.active.where(paid: true).where.not(annual_quota: nil).find_each do |type|
        next unless type.carry_forward_cap.positive?

        HrLite.employees.each do |user|
          balance = LeaveBalance.for(user, type, year)
          next if balance.persisted? && balance.carried_forward.positive?

          carry = LeaveBalance.for(user, type, previous_year)
                              .available(as_of: Date.new(previous_year, 12, 31))
          carry = [ [ carry, type.carry_forward_cap ].min, 0 ].max
          next if carry.zero? && balance.persisted?

          balance.carried_forward = carry
          balance.save!
        end
      end
    end
  end
end
