module HrLite
  module Calculators
    # State-slab professional tax on earned gross. Slabs may carry a
    # feb_extra for the states that top up the last month's deduction.
    #
    # Slabs come from `hr_lite_professional_tax_slabs`, dated per state,
    # falling back to whatever `rates` hash the caller passes for a host that
    # has not seeded yet. A state nobody configured yields zero — and
    # `unconfigured?` is how payroll gets to SAY so, because a confident zero
    # is the failure mode here, not an exception.
    module ProfessionalTax
      def self.call(state:, gross_earned:, period_month:, rates: {})
        slabs = slabs_for(state, period_month, rates)
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

      def self.slabs_for(state, period_month, rates = {})
        stored = stored_slabs(state, period_month)
        return stored if stored.present?

        rates[state.to_s] || []
      end

      # A state with no stored slabs and none in the fallback table. That is
      # NOT the same as a state with no professional tax: Karnataka was the
      # only state ever entered in code, so every other one deducted nothing
      # and nothing said so.
      def self.unconfigured?(state, period_month, rates = {})
        return false if state.to_s == ProfessionalTaxSlab::NO_LEVY

        slabs_for(state, period_month, rates).empty?
      end

      def self.stored_slabs(state, period_month)
        ProfessionalTaxSlab.table_for(state, period_month)
      rescue ActiveRecord::ActiveRecordError
        # Host mid-migration: gem upgraded, db:migrate not yet run.
        []
      end
    end
  end
end
