module HrLite
  # Config-driven statutory rates, keyed by effective date — a budget change
  # is a one-hash edit that gets code review and a spec diff, never an
  # inline-constant hunt.
  #
  # VERIFY WITH A CA before the first run of any new financial year. Adding
  # a year is one new dated entry in CARDS; nothing else changes.
  #
  # When no card exists for a run's financial year the lookup falls back to
  # the newest one it has — payroll cannot simply stop every April — but
  # `warning_for` says so on the run, and `PayrollRunProcessor` puts that
  # sentence in front of every other warning until a card is added.
  module StatutoryRateCard
    def self.r(value) = BigDecimal(value.to_s)
    private_class_method :r

    CARDS = {
      Date.new(2025, 4, 1) => {
        pf: {
          employee_rate: r("0.12"), employer_rate: r("0.12"), eps_rate: r("0.0833"),
          wage_ceiling: r("15000"), eps_wage_ceiling: r("15000"),
          edli_rate: r("0.005"), edli_ceiling: r("15000"), admin_rate: r("0.005")
        },
        esi: { employee_rate: r("0.0075"), employer_rate: r("0.0325"), gross_ceiling: r("21000") },
        pt: {
          # Neither UP nor Uttarakhand levies professional tax today; both
          # ship empty (PT = 0). Karnataka included as a worked template.
          "none" => [],
          "uttar_pradesh" => [],
          "uttarakhand" => [],
          # Inclusive lower bounds. `above: 24999` with a strict `>` taxed a
          # prorated gross of ₹24,999.50, which is below the real threshold.
          "karnataka" => [ { from: r("25000"), monthly: r("200") } ]
        },
        income_tax: {
          "new" => {
            standard_deduction: r("75000"), rebate_cap: r("1200000"), cess_rate: r("0.04"),
            # §115BAC carries marginal relief just above the rebate cap; the
            # old regime does not, so this is a per-regime flag.
            marginal_relief: true,
            slabs: [
              [ r("0"), r("400000"), r("0") ],
              [ r("400000"), r("800000"), r("0.05") ],
              [ r("800000"), r("1200000"), r("0.10") ],
              [ r("1200000"), r("1600000"), r("0.15") ],
              [ r("1600000"), r("2000000"), r("0.20") ],
              [ r("2000000"), r("2400000"), r("0.25") ],
              [ r("2400000"), nil, r("0.30") ]
            ]
          },
          "old" => {
            standard_deduction: r("50000"), rebate_cap: r("500000"), cess_rate: r("0.04"),
            slabs: [
              [ r("0"), r("250000"), r("0") ],
              [ r("250000"), r("500000"), r("0.05") ],
              [ r("500000"), r("1000000"), r("0.20") ],
              [ r("1000000"), nil, r("0.30") ]
            ]
          }
        }
      }
    }.freeze

    def self.for(period_month)
      CARDS[effective_date_for(period_month)]
    end

    # Which card a run will actually use. A month older than every card
    # borrows the earliest one — see `predates_cards?`, which says so.
    def self.effective_date_for(period_month)
      CARDS.keys.sort.reverse.find { |date| date <= period_month } || CARDS.keys.min
    end

    # The card in force is from an EARLIER financial year than the run. The
    # lookup still returns figures — it has to, or payroll would stop dead
    # every April — so the run carries the warning instead.
    def self.stale_for?(period_month)
      FinancialYear.before?(effective_date_for(period_month), period_month)
    end

    # The run is older than every card we ship, so it is being computed on
    # rates that had not been announced yet.
    def self.predates_cards?(period_month)
      period_month < CARDS.keys.min
    end

    # One sentence naming both the run's FY and the card's, or nil when they
    # match. Rendered verbatim in the run's warnings list.
    def self.warning_for(period_month)
      card_fy = FinancialYear.label(effective_date_for(period_month))
      run_fy  = FinancialYear.label(period_month)

      if predates_cards?(period_month)
        "Payroll for FY #{run_fy} is being computed on the FY #{card_fy} " \
        "statutory card — no card ships for a year that early. PF, ESI, PT " \
        "and TDS on this run are not the rates that applied. Verify with your CA."
      elsif stale_for?(period_month)
        "Payroll for FY #{run_fy} is being computed on the FY #{card_fy} " \
        "statutory card — no card ships for FY #{run_fy} yet. PF, ESI, PT and " \
        "TDS on this run use last year's rates. Add a CA-verified card for " \
        "FY #{run_fy} before publishing."
      end
    end
  end
end
