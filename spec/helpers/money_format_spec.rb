require "rails_helper"

RSpec.describe HrLite::ApplicationHelper, type: :helper do
  describe "#hrl_money" do
    it "formats with Indian digit grouping" do
      expect(helper.hrl_money(BigDecimal("0"))).to eq("₹0.00")
      expect(helper.hrl_money(BigDecimal("999"))).to eq("₹999.00")
      expect(helper.hrl_money(BigDecimal("1000"))).to eq("₹1,000.00")
      expect(helper.hrl_money(BigDecimal("75000"))).to eq("₹75,000.00")
      expect(helper.hrl_money(BigDecimal("369000"))).to eq("₹3,69,000.00")
      expect(helper.hrl_money(BigDecimal("1234567.5"))).to eq("₹12,34,567.50")
      expect(helper.hrl_money(BigDecimal("123456789.05"))).to eq("₹12,34,56,789.05")
    end

    it "handles negatives, nil and the configured symbol" do
      expect(helper.hrl_money(BigDecimal("-369000"))).to eq("-₹3,69,000.00")
      expect(helper.hrl_money(nil)).to eq("—")
      HrLite.config.currency_symbol = "$"
      expect(helper.hrl_money(BigDecimal("1000"))).to eq("$1,000.00")
    end
  end

  describe "#hrl_amount_in_words" do
    it "spells Indian-system amounts" do
      expect(helper.hrl_amount_in_words(BigDecimal("369000"))).to eq("Three lakh sixty-nine thousand rupees")
      expect(helper.hrl_amount_in_words(BigDecimal("0"))).to eq("Zero rupees")
    end
  end
end
