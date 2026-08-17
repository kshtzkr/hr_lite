module HrLite
  # A financial year's statutory figures, as data. Named for the table rather
  # than the lookup module (HrLite::StatutoryRateCard) that reads it — hosts
  # and specs call the module, not this.
  class StatutoryRateCardRecord < ApplicationRecord
    include Audited

    self.table_name = "hr_lite_statutory_rate_cards"

    validates :effective_from, presence: true, uniqueness: true
    validate :effective_from_opens_a_financial_year
    validate :carries_every_figure_payroll_reads

    scope :chronological, -> { order(:effective_from) }

    def self.effective_for(period_month)
      where(effective_from: ..period_month).order(effective_from: :desc).first ||
        chronological.first
    end

    def financial_year = FinancialYear.label(effective_from)

    def verified? = verified_by.present? && verified_on.present?

    # The shape SlipBuilder and the calculators expect: symbol keys and
    # BigDecimal everywhere, because JSON gives back strings and floats and
    # a float has no business in a PF calculation.
    def to_card
      {
        pf: deep_decimalize(pf).symbolize_keys,
        esi: deep_decimalize(esi).symbolize_keys,
        pt: {}, # slabs live in their own table — resolved by state at use
        income_tax: income_tax.transform_values { |regime| decimalize_regime(regime) }
      }
    end

    private

    def decimalize_regime(regime)
      regime = regime.symbolize_keys
      regime.merge(
        standard_deduction: Money.d(regime[:standard_deduction]),
        rebate_cap: Money.d(regime[:rebate_cap]),
        cess_rate: Money.d(regime[:cess_rate]),
        marginal_relief: !!regime[:marginal_relief],
        slabs: Array(regime[:slabs]).map { |from, to, rate|
          [ Money.d(from), to.nil? ? nil : Money.d(to), Money.d(rate) ]
        }
      )
    end

    def deep_decimalize(hash)
      hash.to_h { |key, value| [ key, Money.d(value) ] }
    end

    # A card dated mid-year would mean two sets of slabs inside one financial
    # year, and the TDS projector works on an annual figure — there is no
    # sensible answer to "which slabs applied to this year's income" then.
    def effective_from_opens_a_financial_year
      return if effective_from.blank?
      return if effective_from == FinancialYear.start_for(effective_from)

      errors.add(:effective_from, "must be 1 April — a card covers a whole financial year")
    end

    REQUIRED = {
      "pf" => %w[employee_rate employer_rate eps_rate wage_ceiling eps_wage_ceiling
                 edli_rate edli_ceiling admin_rate],
      "esi" => %w[employee_rate employer_rate gross_ceiling]
    }.freeze

    # A card missing a figure does not fail at save time; it fails halfway
    # through computing somebody's salary, as a NoMethodError on nil.
    def carries_every_figure_payroll_reads
      REQUIRED.each do |attribute, keys|
        missing = keys - Array(public_send(attribute)&.keys)
        errors.add(attribute, "is missing #{missing.join(', ')}") if missing.any?
      end

      %w[new old].each do |regime|
        table = income_tax[regime]
        next errors.add(:income_tax, "is missing the #{regime} regime") if table.blank?

        missing = %w[standard_deduction rebate_cap cess_rate slabs] - table.keys
        next errors.add(:income_tax, "#{regime} regime is missing #{missing.join(', ')}") if missing.any?

        # A present-but-empty slab list is the dangerous shape: it validates
        # on key presence and then taxes everybody at zero.
        if Array(table["slabs"]).empty?
          errors.add(:income_tax, "#{regime} regime has no tax slabs — every salary would be taxed at zero")
        end
      end
    end
  end
end
