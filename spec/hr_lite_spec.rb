require "rails_helper"

RSpec.describe HrLite do
  it "has a version number" do
    expect(HrLite::VERSION).not_to be_nil
  end

  describe ".configure" do
    it "yields the configuration" do
      described_class.configure { |c| c.mailer_from = "people@acme.test" }
      expect(described_class.config.mailer_from).to eq("people@acme.test")
    end
  end

  describe ".user_klass" do
    it "resolves the configured class" do
      expect(described_class.user_klass).to eq(User)
    end
  end

  # The tier predicates survive because views, hosts and the notification
  # fan-out all read better asking "is this person leadership" than "do they
  # hold profile.manage at all scope". They are roles all the way down.
  describe ".admin?" do
    it "is true for a role that decides anyone's leave" do
      expect(described_class.admin?(user_with_roles(HrLite::Role::HR))).to be(true)
    end

    it "is false for an employee, an unsaved user and nil" do
      expect(described_class.admin?(user_with_roles(HrLite::Role::EMPLOYEE))).to be(false)
      expect(described_class.admin?(build(:user))).to be(false)
      expect(described_class.admin?(nil)).to be(false)
    end

    it "is false for a manager — deciding your own reports is not running HR" do
      expect(described_class.admin?(user_with_roles(HrLite::Role::MANAGER))).to be(false)
    end

    # The pre-0.6.0 lambdas are migration input now. Somebody the host's own
    # admin_check calls an admin reaches nothing until a role says so.
    it "ignores the configured lambda entirely", no_legacy_bridge: true do
      HrLite.config.admin_check = ->(_user) { true }
      expect(described_class.admin?(user_with_roles(HrLite::Role::EMPLOYEE))).to be(false)
    end
  end

  describe ".can? and .reaches?" do
    it "lets a wider scope answer a narrower question" do
      hr = user_with_roles(HrLite::Role::HR)
      expect(described_class.can?(hr, "leave.approve", scope: :all)).to be(true)
      expect(described_class.can?(hr, "leave.approve", scope: :self)).to be(true)
    end

    it "refuses a narrower scope the wider question" do
      manager = user_with_roles(HrLite::Role::MANAGER)
      expect(described_class.can?(manager, "leave.approve", scope: :team)).to be(true)
      expect(described_class.can?(manager, "leave.approve", scope: :all)).to be(false)
    end

    it "adds roles up, keeping the wider scope" do
      user = user_with_roles(HrLite::Role::MANAGER, HrLite::Role::HR)
      expect(described_class.access_for(user).scope_for("leave.approve")).to eq(:all)
    end

    it "refuses an undeclared permission loudly rather than silently saying no" do
      expect { described_class.can?(create(:user), "leave.aprove") }
        .to raise_error(ArgumentError, /Unknown HrLite permission/)
    end

    it "reaches a report but not a stranger" do
      manager = user_with_roles(HrLite::Role::MANAGER)
      report = create(:employee_profile, manager_id: manager.id).user
      stranger = create(:employee_profile).user

      expect(described_class.reaches?(manager, "leave.approve", report)).to be(true)
      expect(described_class.reaches?(manager, "leave.approve", stranger)).to be(false)
      expect(described_class.reaches?(manager, "leave.approve", manager)).to be(true)
    end
  end

  # Two of the three tiers used to match the user's EMAIL. Every one of these
  # would have granted access before 0.6.0; none of them does now.
  describe "the retired email lists", no_legacy_bridge: true do
    it "grants nothing on their own" do
      HrLite.config.leadership_emails = [ "boss@acme.test" ]
      HrLite.config.superadmin_emails = [ "boss@acme.test" ]
      boss = create(:user, email: "boss@acme.test")
      grant_role(boss, HrLite::Role::EMPLOYEE)

      expect(described_class.leadership?(boss)).to be(false)
      expect(described_class.superadmin?(boss)).to be(false)
      expect(described_class.admin?(boss)).to be(false)
    end

    it "no longer lets a changed email hand somebody the money tier" do
      owner = user_with_roles(HrLite::Role::EMPLOYEE, email: "nobody@acme.test")
      HrLite.config.superadmin_emails = [ "money@acme.test" ]
      owner.update!(email: "money@acme.test")
      HrLite::Current.access_cache = nil

      expect(described_class.superadmin?(owner.reload)).to be(false)
    end

    it "is gone from the configuration object" do
      expect(HrLite.config).not_to respond_to(:legacy_tier_checks)
    end
  end

  describe ".leadership_users" do
    it "resolves the role, not a list of addresses" do
      boss = user_with_roles(HrLite::Role::LEADERSHIP)
      user_with_roles(HrLite::Role::EMPLOYEE)

      expect(described_class.leadership_users).to contain_exactly(boss)
    end

    it "is empty when nobody holds the role" do
      user_with_roles(HrLite::Role::EMPLOYEE)
      expect(described_class.leadership_users).to be_empty
    end

    it "ignores the retired email list", no_legacy_bridge: true do
      HrLite.config.leadership_emails = [ "boss@acme.test" ]
      create(:user, email: "boss@acme.test")

      expect(described_class.leadership_users).to be_empty
    end
  end

  describe ".admin_users" do
    it "is everyone whose roles decide leave for the whole company" do
      hr = user_with_roles(HrLite::Role::HR)
      user_with_roles(HrLite::Role::MANAGER) # team scope only
      user_with_roles(HrLite::Role::EMPLOYEE)

      expect(described_class.admin_users).to contain_exactly(hr)
    end

    it "ignores the host's admin_check", no_legacy_bridge: true do
      HrLite.config.admin_check = ->(_user) { true }
      user_with_roles(HrLite::Role::EMPLOYEE)

      expect(described_class.admin_users).to be_empty
    end
  end

  describe ".users_holding" do
    it "counts a wider scope as holding the narrower one" do
      hr = user_with_roles(HrLite::Role::HR)         # leave.approve => all
      manager = user_with_roles(HrLite::Role::MANAGER) # leave.approve => team

      expect(described_class.users_holding("leave.approve", scope: :team))
        .to contain_exactly(hr, manager)
      expect(described_class.users_holding("leave.approve", scope: :all))
        .to contain_exactly(hr)
    end
  end

  describe ".display_name" do
    it "uses the configured method, falling back name -> email" do
      expect(described_class.display_name(build(:user, name: "Asha"))).to eq("Asha")
      expect(described_class.display_name(build(:user, name: nil, email: "a@b.c"))).to eq("a@b.c")
      expect(described_class.display_name(nil)).to eq("")
    end

    it "falls back to an id label when nothing is readable" do
      HrLite.config.display_name_method = nil
      user = create(:user, name: nil)
      allow(user).to receive(:respond_to?).and_call_original
      allow(user).to receive(:respond_to?).with(:display_name).and_return(false)
      allow(user).to receive(:respond_to?).with(:name).and_return(false)
      allow(user).to receive(:respond_to?).with(:email).and_return(false)

      expect(described_class.display_name(user)).to eq("User ##{user.id}")
    end
  end

  describe ".notify" do
    it "delegates to the configured hook" do
      calls = []
      HrLite.config.notify = ->(**kw) { calls << kw }
      described_class.notify(user: "u", kind: "k", title: "t", body: "b", path: "/p")

      expect(calls).to eq([ { user: "u", kind: "k", title: "t", body: "b", path: "/p" } ])
    end

    it "swallows hook failures" do
      HrLite.config.notify = ->(**) { raise "boom" }
      expect {
        expect(described_class.notify(user: "u", kind: "k", title: "t")).to be_nil
      }.not_to raise_error
    end
  end

  describe ".default_mentionable_users" do
    it "matches name or email, capped at 8, ordered by id" do
      match = create(:user, name: "Khushboo")
      create(:user, name: "Zed", email: "zed@x.test")
      by_mail = create(:user, name: "Zed2", email: "khush@x.test")

      expect(described_class.default_mentionable_users("khu")).to eq([ match, by_mail ])
    end
  end
end
