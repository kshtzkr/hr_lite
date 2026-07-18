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

  describe ".admin?" do
    it "is true for admins via the default admin_check" do
      expect(described_class.admin?(build(:user, :admin))).to be(true)
    end

    it "is false for regular users and nil" do
      expect(described_class.admin?(build(:user))).to be(false)
      expect(described_class.admin?(nil)).to be(false)
    end
  end

  describe ".leadership?" do
    it "matches configured emails case-insensitively" do
      HrLite.config.leadership_emails = [ "Boss@Acme.test " ]
      expect(described_class.leadership?(build(:user, email: "boss@acme.test"))).to be(true)
      expect(described_class.leadership?(build(:user, email: "dev@acme.test"))).to be(false)
    end

    it "is false when no leadership is configured" do
      expect(described_class.leadership?(build(:user))).to be(false)
    end
  end

  describe ".leadership_users" do
    it "resolves configured emails to user records" do
      boss = create(:user, email: "boss@acme.test")
      create(:user, email: "dev@acme.test")
      HrLite.config.leadership_emails = [ "BOSS@acme.test", "ghost@acme.test", "" ]

      expect(described_class.leadership_users).to contain_exactly(boss)
    end

    it "returns none when unconfigured" do
      create(:user)
      expect(described_class.leadership_users).to be_empty
    end
  end

  describe ".admin_users" do
    it "filters by the admin_check" do
      admin = create(:user, :admin)
      create(:user)
      expect(described_class.admin_users).to contain_exactly(admin)
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
