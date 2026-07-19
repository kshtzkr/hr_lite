module HrLite
  # Config-driven statutory rates, keyed by effective date — a budget change
  # is a one-hash edit that gets code review and a spec diff, never an
  # inline-constant hunt.
  #
  # VERIFY WITH A CA before the first run of any new financial year; the
  # FY 2026-27 card ships with FY 2025-26 figures pending confirmation of
  # the Feb 2026 Finance Act.
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
          "karnataka" => [ { above: r("24999"), monthly: r("200") } ]
        },
        income_tax: {
          "new" => {
            standard_deduction: r("75000"), rebate_cap: r("1200000"), cess_rate: r("0.04"),
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
      effective = CARDS.keys.sort.reverse.find { |date| date <= period_month }
      effective ? CARDS[effective] : CARDS[CARDS.keys.min]
    end
  end
end
