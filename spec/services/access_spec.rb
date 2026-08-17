require "rails_helper"

RSpec.describe HrLite::Access, no_legacy_bridge: true do
  let(:user) { create(:user) }

  def with_grants(grants)
    role = HrLite::Role.create!(name: "Custom #{SecureRandom.hex(4)}")
    role.replace_grants!(grants)
    HrLite::RoleAssignment.create!(user_id: user.id, role: role)
    HrLite::Current.access_cache = nil
    described_class.for(user)
  end

  describe "a self-scoped grant" do
    it "reaches the holder and nobody else" do
      access = with_grants("leave.view" => "self")
      other = create(:user)

      expect(access.reaches?("leave.view", user)).to be(true)
      expect(access.reaches?("leave.view", other)).to be(false)
      expect(access.visible_user_ids("leave.view")).to eq([ user.id ])
    end
  end

  describe "a permission that was never granted" do
    it "reaches nobody, not even the holder" do
      access = with_grants("leave.view" => "self")

      expect(access.scope_for("payroll.manage")).to be_nil
      expect(access.reaches?("payroll.manage", user)).to be(false)
      expect(access.visible_user_ids("payroll.manage")).to eq([])
    end
  end

  describe "an `all` grant" do
    # nil means "do not filter" — a caller that read it as an empty list
    # would show leadership nothing at all, which is why `scope_relation`
    # exists rather than callers doing their own `where`.
    it "returns nil visible ids, meaning no filtering" do
      access = with_grants("leave.view" => "all")
      expect(access.visible_user_ids("leave.view")).to be_nil

      relation = HrLite::LeaveRequest.all
      expect(access.scope_relation(relation, "leave.view")).to equal(relation)
    end
  end

  describe "nobody signed in" do
    it "holds nothing" do
      access = described_class.for(nil)

      expect(access.can?("leave.view")).to be(false)
      expect(access.reaches?("leave.view", create(:user))).to be(false)
    end

    it "is also nothing for a subject that is nil" do
      access = with_grants("leave.view" => "all")
      expect(access.reaches?("leave.view", nil)).to be(false)
    end
  end

  describe "the reporting walk" do
    # A loop is only reachable if it closes back on the walker: everyone else
    # in it has a manager inside the loop and so hangs off nothing. Here the
    # manager reports, in the end, to their own report — which EmployeeProfile
    # refuses, and update_column does not.
    it "survives a chain that loops back to the manager" do
      access = with_grants("leave.view" => "team")
      a = create(:employee_profile, manager_id: user.id)
      b = create(:employee_profile, manager_id: a.user_id)
      create(:employee_profile, user: user).update_column(:manager_id, b.user_id)

      expect(access.report_ids).to contain_exactly(a.user_id, b.user_id)
    end

    it "does not treat a manager as their own report twice over" do
      access = with_grants("leave.view" => "team")
      report = create(:employee_profile, manager_id: user.id)

      expect(access.visible_user_ids("leave.view")).to contain_exactly(user.id, report.user_id)
    end
  end

  describe "caching" do
    it "answers from the request cache rather than re-querying" do
      with_grants("leave.view" => "all")
      first = described_class.for(user)

      expect(described_class).not_to receive(:resolve)
      expect(described_class.for(user)).to equal(first)
    end
  end
end
