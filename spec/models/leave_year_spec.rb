require "rails_helper"

RSpec.describe HrLite::LeaveYear do
  describe "calendar years (default)" do
    it "keys, ranges and labels like plain years" do
      expect(described_class.key_for(Date.new(2027, 3, 10))).to eq(2027)
      expect(described_class.range(2027)).to eq(Date.new(2027, 1, 1)..Date.new(2027, 12, 31))
      expect(described_class.label(2027)).to eq("2027")
    end
  end

  describe "July–June years" do
    before { HrLite.config.leave_year_start_month = 7 }

    it "keys dates by the year the July start falls in" do
      expect(described_class.key_for(Date.new(2026, 7, 1))).to eq(2026)
      expect(described_class.key_for(Date.new(2027, 6, 30))).to eq(2026)
      expect(described_class.key_for(Date.new(2027, 7, 1))).to eq(2027)
      expect(described_class.key_for(Date.new(2026, 6, 30))).to eq(2025)
    end

    it "ranges span July to June and labels show both years" do
      expect(described_class.range(2026)).to eq(Date.new(2026, 7, 1)..Date.new(2027, 6, 30))
      expect(described_class.label(2026)).to eq("2026–27")
    end

    it "current_key follows today" do
      travel_to(Date.new(2027, 2, 1)) do
        expect(described_class.current_key).to eq(2026)
      end
    end
  end
end
