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
  # fan-out all call them — but they read off ROLES now, not off a mutable
  # email column. The email lambdas answer only while a host has explicitly
  # asked for them.
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

    it "defers to the configured lambda while legacy_tier_checks is on" do
      HrLite.config.legacy_tier_checks = true
      expect(described_class.admin?(build(:user, :admin))).to be(true)
      expect(described_class.admin?(build(:user))).to be(false)
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

  describe ".leadership? on the legacy lambdas" do
    before { HrLite.config.legacy_tier_checks = true }

    it "matches configured emails case-insensitively" do
      HrLite.config.leadership_emails = [ "Boss@Acme.test " ]
      expect(described_class.leadership?(build(:user, email: "boss@acme.test"))).to be(true)
      expect(described_class.leadership?(build(:user, email: "dev@acme.test"))).to be(false)
    end

    it "is false when no leadership is configured" do
      expect(described_class.leadership?(build(:user))).to be(false)
    end

    # One stray comma in HR_LEADERSHIP_EMAILS put "" on the list, and a user
    # with no email matched it and was handed the tier.
    it "never admits a blank email, however the list is spelled" do
      HrLite.config.leadership_emails = [ "boss@acme.test", "", "  " ]

      expect(described_class.leadership?(build(:user, email: ""))).to be(false)
      expect(described_class.leadership?(build(:user, email: nil))).to be(false)
      expect(described_class.leadership?(build(:user, email: "   "))).to be(false)
      expect(described_class.leadership?(build(:user, email: "boss@acme.test"))).to be(true)
    end
  end

  describe ".superadmin?" do
    before { HrLite.config.legacy_tier_checks = true }

    it "never admits a blank email either" do
      HrLite.config.superadmin_emails = [ "money@acme.test", "" ]

      expect(described_class.superadmin?(build(:user, email: ""))).to be(false)
      expect(described_class.superadmin?(build(:user, email: "money@acme.test"))).to be(true)
    end

    # A list of nothing but blanks is an EMPTY list, not a list nobody is on:
    # it falls back to leadership, exactly as an unset list does.
    it "treats an all-blank list as unconfigured and defers to leadership" do
      HrLite.config.leadership_emails = [ "boss@acme.test" ]
      HrLite.config.superadmin_emails = [ "", "  " ]

      expect(described_class.superadmin?(build(:user, email: "boss@acme.test"))).to be(true)
      expect(described_class.superadmin?(build(:user, email: ""))).to be(false)
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

    it "still resolves configured emails while legacy_tier_checks is on" do
      HrLite.config.legacy_tier_checks = true
      boss = create(:user, email: "boss@acme.test")
      create(:user, email: "dev@acme.test")
      HrLite.config.leadership_emails = [ "BOSS@acme.test", "ghost@acme.test", "" ]

      expect(described_class.leadership_users).to contain_exactly(boss)
    end
  end

  describe ".admin_users" do
    it "is everyone whose roles decide leave for the whole company" do
      hr = user_with_roles(HrLite::Role::HR)
      user_with_roles(HrLite::Role::MANAGER) # team scope only
      user_with_roles(HrLite::Role::EMPLOYEE)

      expect(described_class.admin_users).to contain_exactly(hr)
    end

    it "filters by the admin_check while legacy_tier_checks is on" do
      HrLite.config.legacy_tier_checks = true
      admin = create(:user, :admin)
      create(:user)
      expect(described_class.admin_users).to contain_exactly(admin)
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
