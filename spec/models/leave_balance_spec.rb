require "rails_helper"

RSpec.describe HrLite::LeaveBalance do
  let(:user) { create(:user) }

  describe "#entitled" do
    it "yearly_upfront: full quota plus carry and adjustment" do
      type = create(:leave_type, annual_quota: 12)
      balance = described_class.for(user, type, 2027)
      balance.carried_forward = 3
      balance.adjustment = -1
      expect(balance.entitled(as_of: Date.new(2027, 2, 1))).to eq(14)
    end

    it "monthly: accrues by elapsed month within the year" do
      type = create(:leave_type, :monthly, annual_quota: 12)
      balance = described_class.for(user, type, 2027)
      expect(balance.entitled(as_of: Date.new(2027, 7, 15))).to eq(7)
      expect(balance.entitled(as_of: Date.new(2028, 1, 1))).to eq(12)  # later year: fully accrued
      expect(balance.entitled(as_of: Date.new(2026, 12, 31))).to eq(0) # before the year starts
    end

    it "unlimited types report infinity" do
      type = create(:leave_type, :unpaid_unlimited)
      expect(described_class.for(user, type, 2027).entitled).to eq(Float::INFINITY)
    end
  end

  describe "#used and #available (live recompute)" do
    let(:type) { create(:leave_type, annual_quota: 12) }

    it "sums approved working days in the year, self-healing on holiday changes" do
      create(:leave_request, :approved, user: user, leave_type: type,
             start_date: Date.new(2027, 7, 5), end_date: Date.new(2027, 7, 6))
      balance = described_class.for(user, type, 2027)

      expect(balance.used).to eq(2)
      expect(balance.available(as_of: Date.new(2027, 12, 1))).to eq(10)

      # A holiday declared later inside the approved leave gives the day back.
      create(:holiday, date: Date.new(2027, 7, 6))
      expect(balance.used).to eq(1)
      expect(balance.available(as_of: Date.new(2027, 12, 1))).to eq(11)
    end

    it "ignores pending/rejected requests and other years" do
      create(:leave_request, user: user, leave_type: type,
             start_date: Date.new(2027, 7, 5), end_date: Date.new(2027, 7, 5))
      create(:leave_request, :approved, user: user, leave_type: type,
             start_date: Date.new(2026, 7, 6), end_date: Date.new(2026, 7, 6))

      expect(described_class.for(user, type, 2027).used).to eq(0)
    end
  end

  it "enforces one row per user/type/year" do
    type = create(:leave_type)
    create(:leave_balance, user: user, leave_type: type, year: 2027)
    expect(build(:leave_balance, user: user, leave_type: type, year: 2027)).not_to be_valid
  end
end
