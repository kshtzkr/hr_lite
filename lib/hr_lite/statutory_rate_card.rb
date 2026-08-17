module HrLite
  # Where payroll asks "what were the statutory figures in this month".
  #
  # Cards live in the DATABASE (`hr_lite_statutory_rate_cards`), effective-
  # dated, so adding a financial year is a screen an accountant fills in
  # rather than a gem release. Every April used to be a deadline the gem
  # controlled and the company did not.
  #
  # CARDS below is the SEED — the figures the gem ships with, copied into the
  # table by `hr_lite:seed` and then owned by the install. It is also the
  # fallback for a host that has not migrated or seeded yet, so the lookup
  # never returns nil half-way through computing somebody's salary.
  #
  # When no card covers a run's financial year the lookup still answers —
  # payroll cannot stop dead every 1 April — but `warning_for` says so, and
  # `PayrollRunProcessor` puts that sentence above every other warning.
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
      record = record_for(period_month)
      return record.to_card if record

      CARDS[effective_date_for(period_month)]
    end

    # The stored card a run resolves to, or nil when the table is empty (a
    # host that has not run `hr_lite:seed` yet) and the shipped hash answers
    # instead.
    def self.record_for(period_month)
      return nil unless stored?

      StatutoryRateCardRecord.effective_for(period_month)
    end

    # Deliberately rescued: the lookup is called from payroll, and a host
    # mid-migration — gem upgraded, `db:migrate` not yet run — must fall back
    # to the shipped figures rather than 500.
    def self.stored?
      StatutoryRateCardRecord.table_exists? && StatutoryRateCardRecord.exists?
    rescue ActiveRecord::ActiveRecordError
      false
    end

    # Which card a run will actually use. A month older than every card
    # borrows the earliest one — see `predates_cards?`, which says so.
    def self.effective_date_for(period_month)
      if stored?
        return StatutoryRateCardRecord.effective_for(period_month).effective_from
      end

      CARDS.keys.sort.reverse.find { |date| date <= period_month } || CARDS.keys.min
    end

    def self.earliest_date
      stored? ? StatutoryRateCardRecord.chronological.first.effective_from : CARDS.keys.min
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
      period_month < earliest_date
    end

    # A card exists for the run's year but nobody has signed it off. Ranked
    # below staleness because wrong-year figures are the worse problem, but
    # still worth saying: these numbers decide what lands in a bank account.
    def self.unverified_for(period_month)
      record = record_for(period_month)
      return nil if record.nil? || record.verified? || stale_for?(period_month)

      "The FY #{record.financial_year} statutory card has not been marked " \
      "verified. Check PF, ESI and the tax slabs with your accountant, then " \
      "record who confirmed them on the rate-card screen."
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
