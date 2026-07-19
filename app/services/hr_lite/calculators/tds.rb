module HrLite
  module Calculators
    # Projection-grade TDS (not Form-16-grade — no surcharge, perquisites or
    # HRA-exemption math; the per-slip override is the escape hatch and the
    # slip shows the whole working so "why is my TDS X" answers itself).
    #
    #   projected annual gross = FY gross paid so far + this month
    #                            + structure gross × months remaining after this one
    #   taxable  = projected − standard deduction − (old regime: declared deductions)
    #   annual   = slab tax − 87A rebate (full when taxable ≤ cap) + 4% cess, §288B rounded
    #   monthly  = max((annual − TDS already deducted) / months remaining incl. this, 0)
    module Tds
      Result = Struct.new(:monthly, :projected_annual_gross, :taxable, :annual_tax,
                          :details, keyword_init: true)

      HIGH_INCOME_WARNING_THRESHOLD = BigDecimal("5000000")

      def self.call(regime:, structure_monthly_gross:, gross_earned_this_month:,
                    fy_gross_paid:, fy_tds_paid:, months_remaining:,
                    declared_annual_deductions:, rates:, override: nil)
        table = rates[regime.to_s] || rates["new"]

        if override.present?
          monthly = Money.round_rupee(override)
          return Result.new(monthly: monthly, projected_annual_gross: nil, taxable: nil, annual_tax: nil,
                            details: { "regime" => regime.to_s, "override" => monthly.to_s("F") })
        end

        months_remaining = [ months_remaining.to_i, 1 ].max
        projected = Money.d(fy_gross_paid) + Money.d(gross_earned_this_month) +
                    (Money.d(structure_monthly_gross) * (months_remaining - 1))

        deductions = table[:standard_deduction]
        deductions += Money.d(declared_annual_deductions) if regime.to_s == "old"
        taxable = [ projected - deductions, BigDecimal(0) ].max

        slab_tax = slab_tax_for(taxable, table[:slabs])
        slab_tax = BigDecimal(0) if taxable <= table[:rebate_cap] # §87A full rebate
        annual = Money.round_to_10(slab_tax * (1 + table[:cess_rate]))

        monthly = Money.round_rupee((annual - Money.d(fy_tds_paid)) / months_remaining)
        monthly = BigDecimal(0) if monthly.negative?

        Result.new(
          monthly: monthly,
          projected_annual_gross: Money.round2(projected),
          taxable: Money.round2(taxable),
          annual_tax: annual,
          details: {
            "regime" => regime.to_s,
            "projected_annual_gross" => Money.round2(projected).to_s("F"),
            "standard_deduction" => table[:standard_deduction].to_s("F"),
            "declared_deductions" => (regime.to_s == "old" ? Money.d(declared_annual_deductions).to_s("F") : "0"),
            "taxable" => Money.round2(taxable).to_s("F"),
            "annual_tax_with_cess" => annual.to_s("F"),
            "fy_tds_already_deducted" => Money.d(fy_tds_paid).to_s("F"),
            "months_remaining" => months_remaining.to_s,
            "high_income_review" => (taxable > HIGH_INCOME_WARNING_THRESHOLD).to_s
          }
        )
      end

      def self.slab_tax_for(taxable, slabs)
        slabs.sum(BigDecimal(0)) do |lower, upper, rate|
          next BigDecimal(0) if taxable <= lower

          span_top = upper && taxable > upper ? upper : taxable
          (span_top - lower) * rate
        end
      end
      private_class_method :slab_tax_for
    end
  end
end
