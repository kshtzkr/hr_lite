require "rails_helper"

RSpec.describe HrLite::Money do
  it "coerces to BigDecimal, nil to zero" do
    expect(described_class.d(nil)).to eq(0)
    expect(described_class.d("12.34")).to eq(BigDecimal("12.34"))
    expect(described_class.d(BigDecimal("5"))).to be_a(BigDecimal)
  end

  it "round_rupee: nearest rupee, half-up" do
    expect(described_class.round_rupee("10.49")).to eq(10)
    expect(described_class.round_rupee("10.50")).to eq(11)
  end

  it "ceil_rupee: always up (ESIC rule)" do
    expect(described_class.ceil_rupee("10.01")).to eq(11)
    expect(described_class.ceil_rupee("10.00")).to eq(10)
  end

  it "round2: paise precision" do
    expect(described_class.round2("10.005")).to eq(BigDecimal("10.01"))
  end

  it "round_to_10: section 288B" do
    expect(described_class.round_to_10("104")).to eq(100)
    expect(described_class.round_to_10("105")).to eq(110)
  end
end
