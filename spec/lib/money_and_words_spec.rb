require "rails_helper"

RSpec.describe "Money presentation" do
  describe HrLite::Money do
    it "groups in the Indian system" do
      expect(described_class.format(BigDecimal("1234567.5"))).to eq("₹12,34,567.50")
      expect(described_class.format(BigDecimal("999"))).to eq("₹999.00")
      expect(described_class.format(nil)).to eq("—")
      expect(described_class.format(BigDecimal("-1500"))).to eq("-₹1,500.00")
    end
  end

  describe HrLite::AmountInWords do
    it "spells ordinary amounts" do
      expect(described_class.words(BigDecimal("75000"))).to eq("Seventy-five thousand rupees")
      expect(described_class.words(0)).to eq("Zero rupees")
    end

    # A negative net pay rendered as a bare " rupees": no group cleared its
    # divisor, so nothing was appended at all.
    it "spells a negative amount instead of returning bare rupees" do
      expect(described_class.words(BigDecimal("-1500"))).to eq("Minus one thousand five hundred rupees")
    end

    # Every other group is reduced below 100 by the preceding modulo, but the
    # crore group is unbounded and two_digit only knows 0..99.
    it "spells past a hundred crore" do
      expect(described_class.words(BigDecimal("1230000000"))).to eq("One hundred twenty-three crore rupees")
    end
  end

  describe HrLite::Calculators::ProfessionalTax do
    let(:rates) { HrLite::StatutoryRateCard.for(Date.new(2026, 4, 1))[:pt] }

    it "does not tax a prorated gross just below the threshold" do
      expect(described_class.call(state: "karnataka", gross_earned: BigDecimal("24999.50"),
                                  period_month: Date.new(2026, 6, 1), rates: rates)).to eq(0)
    end

    it "taxes the threshold itself" do
      expect(described_class.call(state: "karnataka", gross_earned: BigDecimal("25000"),
                                  period_month: Date.new(2026, 6, 1), rates: rates)).to eq(200)
    end
  end
end
