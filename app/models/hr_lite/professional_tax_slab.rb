module HrLite
  # One state's professional-tax band. PT is a state levy with its own slabs
  # and its own revision schedule, so it is dated separately from the central
  # rate card rather than living inside it.
  class ProfessionalTaxSlab < ApplicationRecord
    include Audited

    self.table_name = "hr_lite_professional_tax_slabs"

    # A state that genuinely levies nothing. Distinct from a state nobody has
    # configured — see `configured?`, which is what stops payroll quietly
    # deducting zero for a state whose slabs simply were never entered.
    NO_LEVY = "none".freeze

    validates :state, presence: true
    validates :effective_from, presence: true
    validates :from_amount, :monthly, presence: true,
                                      numericality: { greater_than_or_equal_to: 0 }
    validates :feb_extra, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :for_state, ->(state) { where(state: state.to_s) }

    # The bands in force for a state in a given month: the newest effective
    # date that is not in the future, and every band carrying it.
    def self.effective_for(state, period_month)
      dates = for_state(state).where(effective_from: ..period_month)
      newest = dates.maximum(:effective_from)
      return none if newest.nil?

      for_state(state).where(effective_from: newest).order(:from_amount)
    end

    # The shape Calculators::ProfessionalTax reads.
    def self.table_for(state, period_month)
      effective_for(state, period_month).map do |slab|
        { from: Money.d(slab.from_amount), monthly: Money.d(slab.monthly),
          feb_extra: slab.feb_extra && Money.d(slab.feb_extra) }.compact
      end
    end
  end
end
