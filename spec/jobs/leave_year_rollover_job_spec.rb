require "rails_helper"

RSpec.describe HrLite::LeaveYearRolloverJob do
  let(:user) { create(:user) }
  let!(:carry_type) { create(:leave_type, annual_quota: 15, carry_forward_cap: 10) }

  it "carries min(available, cap) into the new year" do
    # 15 entitled in 2027, 2 used => 13 available, capped at 10.
    create(:leave_request, :approved, user: user, leave_type: carry_type,
           start_date: Date.new(2027, 7, 5), end_date: Date.new(2027, 7, 6))

    described_class.perform_now(year: 2028)

    balance = HrLite::LeaveBalance.for(user, carry_type, 2028)
    expect(balance.carried_forward).to eq(10)
  end

  it "clamps negative availability to zero and skips no-carry/unlimited/unpaid types" do
    create(:leave_type, annual_quota: 12, carry_forward_cap: 0)
    create(:leave_type, :unpaid_unlimited, carry_forward_cap: 5)

    balance = HrLite::LeaveBalance.for(user, carry_type, 2027)
    balance.adjustment = -20
    balance.adjustment_note = "correction"
    balance.save!

    described_class.perform_now(year: 2028)

    expect(HrLite::LeaveBalance.for(user, carry_type, 2028).carried_forward).to eq(0)
    expect(HrLite::LeaveBalance.where(year: 2028).count).to be <= HrLite.employees.size
  end

  it "is idempotent — re-runs never clobber an existing carry" do
    described_class.perform_now(year: 2028)
    balance = HrLite::LeaveBalance.for(user, carry_type, 2028)
    expect(balance.carried_forward).to eq(10) if balance.persisted?

    balance.update!(carried_forward: 4, adjustment_note: "manually corrected")
    described_class.perform_now(year: 2028)
    expect(balance.reload.carried_forward).to eq(4)
  end
end
