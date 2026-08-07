require "rails_helper"

RSpec.describe "Leave balance integrity" do
  let(:user) { create(:user, name: "Meera") }
  let(:admin) { create(:user, name: "Rohan", admin: true) }

  describe "the stored adjustment" do
    let(:type) { create(:leave_type, code: "CL", name: "Casual", annual_quota: 12) }

    # Both writers increment the same column. Read-modify-write without the
    # lock meant the comp-off credit and a manual correction could land on
    # the same starting value and one of them would simply vanish.
    it "accumulates across both write paths" do
      HrLite::LeaveBalance.adjust!(user, type, 2026, delta: BigDecimal("2"), note: "correction")
      HrLite::LeaveBalance.adjust!(user, type, 2026, delta: BigDecimal("1"), note: "comp-off")

      balance = HrLite::LeaveBalance.for(user, type, 2026)
      expect(balance.adjustment).to eq(BigDecimal("3"))
      expect(balance.adjustment_note).to include("correction").and include("comp-off")
    end

    it "creates the row on first use without leaving a duplicate behind" do
      2.times { HrLite::LeaveBalance.adjust!(user, type, 2026, delta: BigDecimal("1"), note: "x") }

      expect(HrLite::LeaveBalance.where(user_id: user.id, leave_type_id: type.id, year: 2026).count).to eq(1)
    end
  end

  describe "entitlement after an exit" do
    let(:type) { create(:leave_type, code: "CL", name: "Casual", annual_quota: 12, accrual: "monthly") }

    it "stops accruing on the last working day" do
      create(:employee_profile, user: user,
             date_of_joining: Date.new(2025, 1, 1), date_of_exit: Date.new(2026, 3, 31))
      balance = HrLite::LeaveBalance.for(user, type, 2026)

      # Calendar leave year 2026: Jan, Feb, Mar only — 3 of the 12 months.
      expect(balance.entitled(as_of: Date.new(2026, 12, 31))).to eq(BigDecimal("3"))
    end

    it "still accrues normally for someone who has not left" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2025, 1, 1))
      balance = HrLite::LeaveBalance.for(user, type, 2026)

      expect(balance.entitled(as_of: Date.new(2026, 12, 31))).to eq(BigDecimal("12"))
    end
  end

  describe "approving what was validated" do
    # Creation checks the balance as of the leave START date; approval used
    # to check it as of today, so a future-dated request on a monthly-accrual
    # type passed validation and could then never be approved.
    it "approves a future request whose accrual lands before the leave" do
      type = create(:leave_type, code: "CL", name: "Casual", annual_quota: 12, accrual: "monthly")
      create(:employee_profile, user: user, date_of_joining: Date.new(2020, 1, 1))

      travel_to(Date.new(2026, 2, 10)) do
        request = HrLite::LeaveRequest.create!(
          user: user, leave_type: type,
          start_date: Date.new(2026, 11, 10), end_date: Date.new(2026, 11, 12),
          reason: "Booked flights"
        )

        expect(request.approve!(actor: admin)).to be(true)
        expect(request.reload).to be_approved
      end
    end
  end
end
