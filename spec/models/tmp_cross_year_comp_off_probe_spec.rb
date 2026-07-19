require "rails_helper"

# Throwaway probe — verifies which year's balance a cross-year comp-off
# approval credits, and whether that credit is spendable in the new year.
RSpec.describe "cross-year comp-off probe" do
  let(:user) { create(:user, name: "Meera") }
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let!(:co_type) do
    create(:leave_type, :comp_off, code: "CO", name: "Comp off",
           annual_quota: 0, carry_forward_cap: 0, accrual: "yearly_upfront", paid: true)
  end

  it "shows where the credit lands and whether it can be spent" do
    # Sunday 26 Dec 2027 — request filed in December.
    request = nil
    travel_to(Date.new(2027, 12, 28)) do
      request = HrLite::CompOffRequest.create!(user: user, date_worked: Date.new(2027, 12, 26),
                                               reason: "Year-end departures desk")
    end

    travel_to(Date.new(2028, 1, 5)) do
      expect(request.approve!(actor: admin)).to be(true)

      prev = HrLite::LeaveBalance.for(user, co_type, 2027)
      curr = HrLite::LeaveBalance.for(user, co_type, 2028)
      puts "2027 adjustment=#{prev.adjustment.to_f} available=#{prev.available.to_f}"
      puts "2028 adjustment=#{curr.adjustment.to_f} available=#{curr.available.to_f} entitled=#{curr.entitled.to_f}"

      # Rollover job (even if run now) skips CO: carry_forward_cap 0.
      HrLite::LeaveYearRolloverJob.perform_now(year: 2028)
      curr2 = HrLite::LeaveBalance.for(user, co_type, 2028)
      puts "2028 after rollover carried_forward=#{curr2.carried_forward.to_f} available=#{curr2.available.to_f}"

      # Try to spend it on a future 2028 day (Mon 10 Jan 2028).
      leave = HrLite::LeaveRequest.new(user_id: user.id, leave_type: co_type,
                                       start_date: Date.new(2028, 1, 10), end_date: Date.new(2028, 1, 10),
                                       reason: "comp off")
      puts "2028 leave valid? #{leave.valid?} errors=#{leave.errors.full_messages}"

      # Backdated request into 2027 (past dates — is it even blocked?)
      back = HrLite::LeaveRequest.new(user_id: user.id, leave_type: co_type,
                                      start_date: Date.new(2027, 12, 29), end_date: Date.new(2027, 12, 29),
                                      reason: "backdated")
      puts "backdated 2027 leave valid? #{back.valid?} errors=#{back.errors.full_messages}"
    end
  end
end
