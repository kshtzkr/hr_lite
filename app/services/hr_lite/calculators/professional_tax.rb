module HrLite
  module Calculators
    # State-slab professional tax on earned gross. Unknown states and
    # states without PT (UP, Uttarakhand) simply yield zero. Slabs may
    # carry a feb_extra for states that top up the February deduction.
    module ProfessionalTax
      def self.call(state:, gross_earned:, period_month:, rates:)
        slabs = rates[state.to_s] || []
        earned = Money.d(gross_earned)

        # `from:` is an INCLUSIVE lower bound — ₹25,000 is taxed, ₹24,999.50 is
        # not. The older exclusive `above:` form still works so a host's own
        # slab table keeps functioning, but it cannot express that boundary on
        # a decimal amount: `above: 24999` taxed a prorated ₹24,999.50.
        slab = slabs.reverse.find { |row| row[:from] ? earned >= row[:from] : earned > row[:above] }
        return BigDecimal(0) unless slab

        amount = slab[:monthly]
        amount += slab[:feb_extra] if slab[:feb_extra] && period_month.month == 2
        Money.round_rupee(amount)
      end
    end
  end
end
