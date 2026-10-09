module HrLite
  # Somebody's income tax for the financial year, worked out now from what
  # is true now: the salary structure in force, the slips already paid, and
  # their declaration with the legal limits applied. Both regimes, with every
  # step shown, so "why is my TDS X" answers itself. Uses the same TDS
  # calculator payroll uses, so the screen and the slip never disagree.
  class TaxComputation
    Sheet = Struct.new(:regime, :gross, :hra_exemption, :standard_deduction, :deductions, :taxable,
                       :slabs, :annual_tax, :tds_paid, :remaining, :months_left, :monthly, keyword_init: true)

    attr_reader :user, :month, :structure, :declaration, :paid

    def initialize(user:, on: Date.current, declaration: nil)
      @user = user
      @month = on.beginning_of_month
      @profile = EmployeeProfile.find_by(user_id: user.id)
      @structure = SalaryStructure.effective_for(user, @month)
      @declaration = declaration || TaxDeclaration.for(user, @month)
      @paid = SalarySlip.fy_to_date(user, @month)
    end

    def regime = declaration&.regime || @profile&.tax_regime || "new"

    def months_left = month.month >= 4 ? 16 - month.month : 4 - month.month

    def paid_gross = paid[:gross] + Money.d(@profile&.fy_opening_gross)

    def projected_gross = Money.d(structure&.monthly_gross) * months_left

    def sheets = @sheets ||= TaxDeclaration::REGIMES.to_h { |name| [ name, sheet(name) ] }

    def chosen = sheets[regime]

    # The regime that costs less this year, and by how much.
    def saving
      new_tax, old_tax = sheets.values_at("new", "old").map(&:annual_tax)
      new_tax <= old_tax ? [ "new", old_tax - new_tax ] : [ "old", new_tax - old_tax ]
    end

    private

    def sheet(name)
      rates = StatutoryRateCard.for(month)[:income_tax]
      table = rates[name]
      rows = name == "old" && declaration && structure ? declaration.deduction_rows(structure: structure) : []
      hra = rows.find { |row| row.section == "hra" }&.allowed || BigDecimal(0)
      tds_paid = paid[:tds] + Money.d(@profile&.fy_opening_tds)
      result = Calculators::Tds.call(
        regime: name, structure_monthly_gross: Money.d(structure&.monthly_gross),
        gross_earned_this_month: Money.d(structure&.monthly_gross), fy_gross_paid: paid_gross,
        fy_tds_paid: tds_paid, months_remaining: months_left,
        declared_annual_deductions: rows.sum(BigDecimal(0), &:allowed), rates: rates
      )
      Sheet.new(regime: name, gross: result.projected_annual_gross, hra_exemption: hra,
                standard_deduction: table[:standard_deduction], deductions: rows.reject { |row| row.section == "hra" },
                taxable: result.taxable, slabs: Calculators::Tds.slab_rows(result.taxable, table[:slabs]),
                annual_tax: result.annual_tax, tds_paid: tds_paid,
                remaining: [ result.annual_tax - tds_paid, BigDecimal(0) ].max, months_left: months_left, monthly: result.monthly)
    end
  end
end
