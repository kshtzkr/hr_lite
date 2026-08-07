module HrLite
  # Assembles one employee's slip numbers for a run. Sequence: attendance
  # summary -> proration -> PF -> ESI -> PT -> TDS -> totals. Every line is
  # rounded by its own statutory rule exactly once; net pay is a plain
  # subtraction of already-rounded lines, so nothing can drift.
  class SlipBuilder
    def self.call(run:, user:, structure:, profile:, lop_override: nil, tds_override: nil)
      new(run, user, structure, profile, lop_override, tds_override).call
    end

    def initialize(run, user, structure, profile, lop_override, tds_override)
      @run = run
      @user = user
      @structure = structure
      @profile = profile
      @lop_override = lop_override
      @tds_override = tds_override
      @rates = StatutoryRateCard.for(run.period_month)
    end

    def call
      summary = AttendanceSummary.for(user: @user, month: @run.period_month)
      days_in_month = summary[:days_in_month]
      # Clamped defensively: a stored negative override (written before the
      # controller bounded them) would otherwise pay more days than the month has.
      lop = [ Money.d(@lop_override || summary[:lop_days]), BigDecimal(0) ].max
      payable = [ Money.d(days_in_month) - Money.d(summary[:out_of_window]) - lop, Money.d(0) ].max

      earnings = Calculators::Proration.call(
        structure: @structure, payable_days: payable, days_in_month: days_in_month
      )
      gross_earned = earnings.sum(BigDecimal(0)) { |row| row[:amount] }
      basic_earned = earnings.find { |row| row[:code] == "basic" }&.fetch(:amount) || BigDecimal(0)

      deductions = []
      employer_costs = {}

      if @structure.pf_applicable
        pf = Calculators::Pf.call(basic_earned: basic_earned,
                                  on_full_basic: @structure.pf_on_full_basic, rates: @rates[:pf])
        deductions << { code: "pf_employee", label: "Provident fund", amount: pf.employee,
                        meta: { pf_wage: pf.pf_wage.to_s("F") } }
        employer_costs.merge!(
          pf_eps: pf.employer_eps, pf_epf: pf.employer_epf,
          edli: pf.edli, pf_admin: pf.admin_charges
        )
      end

      esi = Calculators::Esi.call(monthly_gross: @structure.monthly_gross, gross_earned: gross_earned,
                                  applicable: @structure.esi_applicable, rates: @rates[:esi])
      if esi.applicable?
        deductions << { code: "esi_employee", label: "ESI", amount: esi.employee }
        employer_costs[:esi_employer] = esi.employer
      end

      pt = Calculators::ProfessionalTax.call(state: @structure.pt_state, gross_earned: gross_earned,
                                             period_month: @run.period_month, rates: @rates[:pt])
      deductions << { code: "pt", label: "Professional tax", amount: pt } if pt.positive?

      fy = SalarySlip.fy_to_date(@user, @run.period_month)
      tds = Calculators::Tds.call(
        regime: @profile.tax_regime,
        structure_monthly_gross: @structure.monthly_gross,
        gross_earned_this_month: gross_earned,
        fy_gross_paid: fy[:gross],
        fy_tds_paid: fy[:tds],
        months_remaining: months_remaining_in_fy,
        declared_annual_deductions: @profile.declared_annual_deductions,
        rates: @rates[:income_tax],
        override: @tds_override
      )
      deductions << { code: "tds", label: "Income tax (TDS)", amount: tds.monthly } if tds.monthly.positive?

      total_deductions = deductions.sum(BigDecimal(0)) { |row| row[:amount] }

      {
        period_month: @run.period_month,
        days_in_month: days_in_month,
        payable_days: payable,
        lop_days: Money.d(summary[:lop_days]),
        lop_override: @lop_override,
        tds_override: @tds_override,
        earnings: serialize_rows(earnings),
        deductions: serialize_rows(deductions),
        employer_costs: employer_costs.transform_values { |v| v.to_s("F") }.to_json,
        tax_details: tds.details.to_json,
        gross_earnings: gross_earned,
        total_deductions: total_deductions,
        # A heavy-LOP month can leave TDS (projected from the full structure)
        # larger than what was actually earned. Nobody is paid a negative
        # salary; PayrollRunProcessor warns when this floor bites.
        net_pay: [ gross_earned - total_deductions, BigDecimal(0) ].max,
        computed_at: Time.current
      }
    end

    private

    # Months left in the Indian FY (Apr–Mar) including the run month itself:
    # April = 12, December = 4, January = 3, March = 1. Capped at the exit
    # month for a leaver, so a final settlement is not spread over months
    # that will never be paid.
    def months_remaining_in_fy
      month = @run.period_month.month
      calendar = month >= 4 ? (16 - month) : (4 - month)
      exit_date = @profile&.date_of_exit
      return calendar if exit_date.nil? || exit_date < @run.period_month

      [ calendar, months_between(@run.period_month, exit_date) ].min
    end

    def months_between(from, to)
      (to.year * 12 + to.month) - (from.year * 12 + from.month) + 1
    end

    def serialize_rows(rows)
      rows.map { |row|
        row.transform_values { |value| value.is_a?(BigDecimal) ? value.to_s("F") : value }
      }.to_json
    end
  end
end
