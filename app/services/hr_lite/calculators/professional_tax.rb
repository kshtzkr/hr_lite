module HrLite
  module Calculators
    # State-slab professional tax on earned gross. Unknown states and
    # states without PT (UP, Uttarakhand) simply yield zero. Slabs may
    # carry a feb_extra for states that top up the February deduction.
    module ProfessionalTax
      def self.call(state:, gross_earned:, period_month:, rates:)
        slabs = rates[state.to_s] || []
        earned = Money.d(gross_earned)

        slab = slabs.reverse.find { |row| earned > row[:above] }
        return BigDecimal(0) unless slab

        amount = slab[:monthly]
        amount += slab[:feb_extra] if slab[:feb_extra] && period_month.month == 2
        Money.round_rupee(amount)
      end
    end
  end
end
