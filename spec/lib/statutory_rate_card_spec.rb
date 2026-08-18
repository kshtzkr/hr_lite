require "rails_helper"

RSpec.describe HrLite::StatutoryRateCard do
  it "returns the newest card effective on or before the period" do
    expect(described_class.for(Date.new(2026, 6, 1))).to eq(described_class::CARDS[Date.new(2025, 4, 1)])
  end

  it "falls back to the oldest card for prehistoric periods" do
    expect(described_class.for(Date.new(2020, 1, 1))).to eq(described_class::CARDS[described_class::CARDS.keys.min])
  end

  it "every card is structurally complete and frozen" do
    described_class::CARDS.each_value do |card|
      expect(card[:pf].keys).to include(:employee_rate, :employer_rate, :eps_rate, :wage_ceiling,
                                        :eps_wage_ceiling, :edli_rate, :edli_ceiling, :admin_rate)
      expect(card[:esi].keys).to include(:employee_rate, :employer_rate, :gross_ceiling)
      expect(card[:pt]).to include("none")
      %w[new old].each do |regime|
        expect(card[:income_tax][regime].keys).to include(:standard_deduction, :rebate_cap, :cess_rate, :slabs)
        expect(card[:income_tax][regime][:slabs].last[1]).to be_nil # open-ended top slab
      end
    end
    expect(described_class::CARDS).to be_frozen
  end

  it "uses BigDecimal everywhere" do
    card = described_class.for(Date.current)
    expect(card[:pf][:employee_rate]).to be_a(BigDecimal)
    expect(card[:income_tax]["new"][:slabs].flatten.compact).to all(be_a(BigDecimal))
  end

  # A silent fallback is how a whole financial year gets paid on last year's
  # PF ceiling and last year's slabs. The lookup still answers — payroll
  # cannot stop every April — but it has to say what it did.
  describe "staleness" do
    let(:newest) { described_class::CARDS.keys.max }

    it "is not stale inside the card's own financial year" do
      march = Date.new(newest.year + 1, 3, 1) # same FY as an April card
      expect(described_class).not_to be_stale_for(march)
      expect(described_class.warning_for(march)).to be_nil
    end

    it "is stale once the run crosses into a later financial year" do
      next_fy = Date.new(newest.year + 1, 4, 1)
      expect(described_class).to be_stale_for(next_fy)
      expect(described_class.warning_for(next_fy))
        .to include("FY #{HrLite::FinancialYear.label(next_fy)}", "last year's rates", "CA-verified")
    end

    it "names both financial years so the reader can see the gap" do
      run = Date.new(newest.year + 2, 6, 1)
      expect(described_class.warning_for(run))
        .to include("FY #{HrLite::FinancialYear.label(run)}",
                    "FY #{HrLite::FinancialYear.label(newest)}")
    end

    it "warns differently for a period older than every card" do
      ancient = described_class::CARDS.keys.min.prev_year
      expect(described_class).to be_predates_cards(ancient)
      expect(described_class.warning_for(ancient)).to include("no card ships for a year that early")
    end
  end
end
