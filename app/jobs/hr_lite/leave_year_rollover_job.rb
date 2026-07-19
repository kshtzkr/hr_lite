module HrLite
  # Leave-year rollover (host schedules it on the leave year's first day —
  # Jan 1 for calendar years, Jul 1 for July–June years): materialize
  # carry-forward into the new year's balance rows. Idempotent — a balance
  # whose carry has already been written is never touched again (manual
  # adjustments stay safe).
  class LeaveYearRolloverJob < ActiveJob::Base
    queue_as :default

    def perform(year: LeaveYear.current_key)
      previous_year = year - 1

      LeaveType.active.where(paid: true).where.not(annual_quota: nil).find_each do |type|
        next unless type.carry_forward_cap.positive?

        HrLite.employees.each do |user|
          balance = LeaveBalance.for(user, type, year)
          next if balance.persisted? && balance.carried_forward.positive?

          carry = LeaveBalance.for(user, type, previous_year)
                              .available(as_of: LeaveYear.range(previous_year).last)
          carry = [ [ carry, type.carry_forward_cap ].min, 0 ].max
          next if carry.zero? && balance.persisted?

          balance.carried_forward = carry
          balance.save!
        end
      end
    end
  end
end
