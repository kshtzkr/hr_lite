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
end
