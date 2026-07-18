require "rails_helper"

RSpec.describe HrLite::AttendanceSummary do
  let(:user) { create(:user) }
  # July 2027: 31 days, sat_sun weekends = 9 days (5 Sat + 4 Sun), 22 working days.
  let(:month) { Date.new(2027, 7, 1) }

  def summary
    described_class.for(user: user, month: month)
  end

  context "for a fully closed month" do
    around { |example| travel_to(Date.new(2027, 8, 5)) { example.run } }

    it "counts a plain month: everything unpunched is LOP" do
      s = summary
      expect(s[:weekend]).to eq(9)
      expect(s[:absent]).to eq(22)
      expect(s[:payable_days]).to eq(9)
      expect(s[:lop_days]).to eq(22)
      expect(s[:payable_days] + s[:lop_days]).to eq(31)
    end

    it "pays holidays, presence and paid leave; LWP and absence are LOP" do
      create(:holiday, date: Date.new(2027, 7, 5))
      (6..9).each { |d| create(:attendance_record, :checked_in, user: user, date: Date.new(2027, 7, d)) }

      paid_type = create(:leave_type, annual_quota: 12)
      create(:leave_request, :approved, user: user, leave_type: paid_type,
             start_date: Date.new(2027, 7, 12), end_date: Date.new(2027, 7, 13))

      lwp = create(:leave_type, :unpaid_unlimited)
      create(:leave_request, :approved, user: user, leave_type: lwp,
             start_date: Date.new(2027, 7, 14), end_date: Date.new(2027, 7, 14))

      s = summary
      expect(s[:holiday]).to eq(1)
      expect(s[:present]).to eq(4)
      expect(s[:paid_leave]).to eq(2)
      expect(s[:unpaid_leave]).to eq(1)
      # payable: 9 weekend + 1 holiday + 4 present + 2 paid leave = 16
      expect(s[:payable_days]).to eq(16)
      # lop: 1 LWP + 14 absent working days
      expect(s[:lop_days]).to eq(15)
      expect(s[:payable_days] + s[:lop_days]).to eq(31)
    end

    it "splits half-day punches" do
      create(:attendance_record, :checked_in, user: user, date: Date.new(2027, 7, 6), status: "half_day")
      s = summary
      expect(s[:half_day]).to eq(1)
      expect(s[:payable_days]).to eq(BigDecimal("9.5"))
      expect(s[:lop_days]).to eq(BigDecimal("21.5"))
    end

    it "half-day paid leave + punched other half is fully payable" do
      paid_type = create(:leave_type, annual_quota: 12)
      create(:leave_request, :approved, user: user, leave_type: paid_type, half_day: true,
             start_date: Date.new(2027, 7, 6), end_date: Date.new(2027, 7, 6))
      create(:attendance_record, :checked_in, user: user, date: Date.new(2027, 7, 6))

      s = summary
      expect(s[:paid_leave]).to eq(BigDecimal("0.5"))
      expect(s[:present]).to eq(BigDecimal("0.5"))
      expect(s[:payable_days]).to eq(10)
      expect(s[:lop_days]).to eq(21)
    end

    it "half-day paid leave with no punch loses the other half" do
      paid_type = create(:leave_type, annual_quota: 12)
      create(:leave_request, :approved, user: user, leave_type: paid_type, half_day: true,
             start_date: Date.new(2027, 7, 6), end_date: Date.new(2027, 7, 6))

      s = summary
      expect(s[:payable_days]).to eq(BigDecimal("9.5"))
      expect(s[:lop_days]).to eq(BigDecimal("21.5"))
    end

    it "half-day UNPAID leave: leave half is LOP even when punched" do
      lwp = create(:leave_type, :unpaid_unlimited)
      create(:leave_request, :approved, user: user, leave_type: lwp, half_day: true,
             start_date: Date.new(2027, 7, 6), end_date: Date.new(2027, 7, 6))
      create(:attendance_record, :checked_in, user: user, date: Date.new(2027, 7, 6))

      s = summary
      expect(s[:unpaid_leave]).to eq(BigDecimal("0.5"))
      expect(s[:payable_days]).to eq(BigDecimal("9.5"))
      expect(s[:lop_days]).to eq(BigDecimal("21.5"))
    end
  end

  context "mid-month" do
    it "excludes future working days from both sides" do
      travel_to(Date.new(2027, 7, 15)) do
        create(:attendance_record, :checked_in, user: user, date: Date.new(2027, 7, 15))
        s = summary
        # 16 future days, of which 5 are weekends (17,18,24,25,31) — weekends
        # classify as weekend (payable) regardless of past/future; only future
        # WORKING days are upcoming. Payroll always runs on closed months.
        expect(s[:upcoming]).to eq(11)
        expect(s[:payable_days] + s[:lop_days] + s[:upcoming]).to eq(31)
      end
    end
  end

  describe ".for_all" do
    it "returns summaries keyed by user id" do
      other = create(:user)
      travel_to(Date.new(2027, 8, 2)) do
        result = described_class.for_all(users: [ user, other ], month: month)
        expect(result.keys).to contain_exactly(user.id, other.id)
        expect(result[user.id][:days_in_month]).to eq(31)
      end
    end
  end
end
