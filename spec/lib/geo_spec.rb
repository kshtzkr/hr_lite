require "rails_helper"

RSpec.describe HrLite::Geo do
  # Connaught Place to India Gate is ~2.2 km.
  CP = [ 28.6315, 77.2167 ].freeze
  INDIA_GATE = [ 28.6129, 77.2295 ].freeze

  it "computes known distances within 1%" do
    d = described_class.distance_m(*CP, *INDIA_GATE)
    expect(d).to be_within(0.01 * 2400).of(2400)
  end

  it "is zero for identical points" do
    expect(described_class.distance_m(*CP, *CP)).to eq(0)
  end

  it "accepts BigDecimal/string inputs" do
    d = described_class.distance_m(BigDecimal("28.6315"), "77.2167", *INDIA_GATE)
    expect(d).to be > 2000
  end
end
