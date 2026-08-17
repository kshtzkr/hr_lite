require "rails_helper"

RSpec.describe HrLite::FinancialYear do
  describe ".start_for" do
    it "opens the year on 1 April" do
      expect(described_class.start_for(Date.new(2026, 4, 1))).to eq(Date.new(2026, 4, 1))
      expect(described_class.start_for(Date.new(2026, 12, 31))).to eq(Date.new(2026, 4, 1))
    end

    it "puts January to March in the year that opened the previous April" do
      expect(described_class.start_for(Date.new(2027, 3, 31))).to eq(Date.new(2026, 4, 1))
      expect(described_class.start_for(Date.new(2027, 1, 1))).to eq(Date.new(2026, 4, 1))
    end
  end

  describe ".label" do
    it "reads the way an Indian payslip reads" do
      expect(described_class.label(Date.new(2026, 4, 1))).to eq("2026-27")
      expect(described_class.label(Date.new(2027, 3, 1))).to eq("2026-27")
    end

    it "pads the second half across a century boundary" do
      expect(described_class.label(Date.new(2099, 6, 1))).to eq("2099-00")
    end
  end

  describe ".before?" do
    it "compares years, not dates" do
      expect(described_class).to be_before(Date.new(2026, 3, 1), Date.new(2026, 4, 1))
      expect(described_class).not_to be_before(Date.new(2026, 4, 1), Date.new(2027, 3, 1))
    end
  end
end
