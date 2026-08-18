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
      # `upcoming` is normally zero — PayrollRun refuses a month that has not
      # ended — but subtracting it means a legacy run for an open month cannot
      # pay for days nobody has worked yet.
      payable = [ Money.d(days_in_month) - Money.d(summary[:out_of_window]) -
                  Money.d(summary[:upcoming]) - lop, Money.d(0) ].max

      earnings = Calculators::Proration.call(
        structure: @structure, payable_days: payable, days_in_month: days_in_month
      )
      # One-off heads for this month: a bonus, arrears after a backdated
      # revision, a reimbursement. A prorated head is scaled like basic; a
      # bonus is not halved because somebody joined mid-month.
      extra_earnings, extra_deductions = one_off_lines(payable, days_in_month)
      earnings += extra_earnings

      gross_earned = earnings.sum(BigDecimal(0)) { |row| row[:amount] }
      basic_earned = earnings.find { |row| row[:code] == "basic" }&.fetch(:amount) || BigDecimal(0)
      # ESI is assessed on wages, and a reimbursement is not one. Heads that
      # opt out are excluded from the gross it reads.
      esi_gross = gross_earned - earnings.sum(BigDecimal(0)) { |row| row[:excluded_from_esi] ? row[:amount] : 0 }

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

      esi = Calculators::Esi.call(monthly_gross: esi_reference_gross, gross_earned: esi_gross,
                                  applicable: @structure.esi_applicable, rates: @rates[:esi])
      if esi.applicable?
        deductions << { code: "esi_employee", label: "ESI", amount: esi.employee }
        employer_costs[:esi_employer] = esi.employer
      end

      pt = Calculators::ProfessionalTax.call(state: @structure.pt_state, gross_earned: gross_earned,
                                             period_month: @run.period_month, rates: @rates[:pt])
      deductions << { code: "pt", label: "Professional tax", amount: pt } if pt.positive?

      deductions.concat(extra_deductions)
      loan = loan_instalment
      deductions << loan if loan

      fy = SalarySlip.fy_to_date(@user, @run.period_month)
      tds = Calculators::Tds.call(
        regime: @profile.tax_regime,
        structure_monthly_gross: @structure.monthly_gross,
        gross_earned_this_month: gross_earned,
        # Plus anything paid this FY that this install never ran — a previous
        # employer, or the months before payroll was switched on. Without it a
        # mid-year start projects those months as zero income and can land the
        # whole year under the rebate cap.
        fy_gross_paid: fy[:gross] + Money.d(@profile.fy_opening_gross),
        fy_tds_paid: fy[:tds] + Money.d(@profile.fy_opening_tds),
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
        # Recorded so the slip can say WHY a mid-month joiner's payable days
        # are short, instead of looking like days went missing.
        out_of_window_days: Money.d(summary[:out_of_window]),
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

    # Splits this month's one-off lines into earnings and deductions, in the
    # component order an install configured. Returns [earnings, deductions].
    def one_off_lines(payable, days_in_month)
      rows = PayrollLineItem.for_slip(@user, @run.period_month)
                            .sort_by { |item| [ item.component.position, item.component.label ] }
      earnings = []
      deductions = []

      rows.each do |item|
        component = item.component
        amount = if component.prorated
          Money.round2(item.amount * (Money.d(payable) / Money.d(days_in_month)))
        else
          item.amount
        end
        next unless amount.positive?

        row = { code: component.code, label: component.label, amount: amount }
        if component.earning?
          earnings << row.merge(excluded_from_esi: !component.counts_for_esi)
        else
          deductions << row
        end
      end

      [ earnings, deductions ]
    end

    # The month's loan instalment, as one deduction line. Computed here and
    # BOOKED only when the run is finalized — a draft is recomputed freely,
    # and booking at compute would take a repayment on every pass.
    def loan_instalment
      total = Loan.active.where(user_id: @user.id).sum(BigDecimal(0)) do |loan|
        loan.instalment_for(@run.period_month)
      end
      return nil unless total.positive?

      { code: "loan_repayment", label: "Loan repayment", amount: total }
    end

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

    # ESIC contribution periods run April–September and October–March.
    # Eligibility is fixed for the whole period, so it is decided on the
    # salary in force on its first day — re-deciding it every month dropped
    # someone out of ESI the moment a mid-period raise crossed the ceiling.
    def esi_reference_gross
      month = @run.period_month
      start = if month.month.between?(4, 9)
        Date.new(month.year, 4, 1)
      elsif month.month >= 10
        Date.new(month.year, 10, 1)
      else
        Date.new(month.year - 1, 10, 1)
      end

      # No structure that far back (a mid-period joiner) — their own is the
      # only salary this period has ever had.
      (SalaryStructure.effective_for(@user, start) || @structure).monthly_gross
    end

    def serialize_rows(rows)
      rows.map { |row|
        row.transform_values { |value| value.is_a?(BigDecimal) ? value.to_s("F") : value }
      }.to_json
    end
  end
end
