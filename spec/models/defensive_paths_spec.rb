require "rails_helper"

# The rescue clauses and races that only fire when something else has already
# gone wrong. They are the paths least likely to be exercised by hand and the
# ones whose failure is hardest to diagnose afterwards, so they are pinned
# here deliberately.
RSpec.describe "Defensive paths" do
  let(:leader) { create(:user, email: "lead@x.test") }

  describe HrLite::PayrollRunProcessor do
    around { |example| travel_to(Date.new(2027, 7, 5)) { example.run } }

    it "warns when an override makes deductions exceed earnings" do
      profile = create(:employee_profile)
      create(:salary_structure, user: profile.user, basic: 20000, hra: nil, special_allowance: nil)
      run = create(:payroll_run, period_month: Date.new(2027, 6, 1))
      run.compute!(actor: leader)

      # A TDS override larger than the whole month's pay. Net pay floors at
      # zero rather than going negative, and the run has to say so.
      run.salary_slips.first.update!(tds_override: BigDecimal("999999"))
      run.compute!(actor: leader)

      expect(run.reload.warnings.join).to include("Deductions exceed earnings", "floored at zero")
      expect(run.salary_slips.first.net_pay).to eq(0)
    end
  end

  describe HrLite::Resignation do
    it "accepts the resignation even when the host cannot revoke access" do
      employee = create(:employee_profile).user
      resignation = described_class.create!(user: employee, proposed_last_day: Date.current + 30)
      HrLite.config.offboard_user = ->(_user) { raise "SSO is down" }

      expect(Rails.logger).to receive(:error).with(/offboard_user failed: RuntimeError: SSO is down/)
      # Access is revoked inline only when the last day has already arrived —
      # a notice period is revoked later, from the employee page.
      expect { resignation.accept!(actor: leader, last_day: Date.current) }.not_to raise_error
      expect(resignation.reload.status).to eq("accepted")
    end
  end

  describe HrLite::LeaveBalance do
    # Two approvals racing for the same [user, type, year] both find nothing
    # and both insert; the unique index rejects the loser, which then has to
    # pick up the row the winner wrote instead of blowing up.
    it "picks up the row a concurrent request created a moment earlier" do
      user = create(:user)
      type = create(:leave_type)
      year = HrLite::LeaveYear.current_key
      winner = described_class.create!(user_id: user.id, leave_type_id: type.id, year: year)

      # The first look-up misses, as it would just before the other request
      # commits, so this one tries to insert and loses. The retry — which
      # find_by! runs through find_by — then sees the winner's row.
      allow(described_class).to receive(:find_by).and_return(nil, winner)

      expect(described_class.lock_for(user, type, year)).to eq(winner)
    end
  end
end
