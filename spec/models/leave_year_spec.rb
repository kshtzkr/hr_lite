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

    it "zero-pads single-digit short years in labels" do
      expect(described_class.label(2005)).to eq("2005–06")
      expect(described_class.label(2099)).to eq("2099–00")
    end
  end

  describe "configuration guardrails" do
    it "accepts integer-ish values and rejects garbage at assignment" do
      HrLite.config.leave_year_start_month = "7"
      expect(described_class.start_month).to eq(7)

      expect { HrLite.config.leave_year_start_month = 0 }.to raise_error(ArgumentError, /1\.\.12/)
      expect { HrLite.config.leave_year_start_month = 13 }.to raise_error(ArgumentError, /1\.\.12/)
      expect { HrLite.config.leave_year_start_month = "july" }.to raise_error(ArgumentError)
    end
  end

  describe "rollover time-zone safety" do
    it "keys the default year in the HR time zone, not the host process zone" do
      HrLite.config.leave_year_start_month = 7
      user = create(:user)
      type = create(:leave_type, annual_quota: 12, carry_forward_cap: 5)
      HrLite::LeaveBalance.for(user, type, 2026).tap { |b| b.adjustment = 2; b.save! }

      # 30 Jun 20:00 UTC = 1 Jul 01:30 IST: the HR year has already rolled.
      # A UTC-zoned host would key 2026 and re-run last year's rollover;
      # the IST-aware job must materialize the 2026 -> 2027 carry.
      travel_to(Time.utc(2027, 6, 30, 20, 0)) do
        Time.use_zone("UTC") { HrLite::LeaveYearRolloverJob.new.perform }
      end
      expect(HrLite::LeaveBalance.for(user, type, 2027).carried_forward).to be > 0
    end
  end
end
