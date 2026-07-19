require "rails_helper"

RSpec.describe HrLite::Kudo do
  describe "validations" do
    it "requires a message within 1000 chars" do
      expect(build(:kudo, message: nil)).not_to be_valid
      expect(build(:kudo, message: "x" * 1001)).not_to be_valid
      expect(build(:kudo, message: "x")).to be_valid
    end

    it "accepts only known badges (or blank)" do
      expect(build(:kudo, badge: "team_player")).to be_valid
      expect(build(:kudo, badge: "")).to be_valid
      expect(build(:kudo, badge: "made_up")).not_to be_valid
    end
  end

  describe "#deletable_by?" do
    let(:kudo) { create(:kudo) }

    it "allows the giver within the window, not after" do
      expect(kudo.deletable_by?(kudo.giver)).to be(true)
      travel_to(16.minutes.from_now) do
        expect(kudo.deletable_by?(kudo.giver)).to be(false)
      end
    end

    it "allows admins and leadership any time, denies others and nil" do
      admin = create(:user, :admin)
      leader = create(:user, email: "lead@x.test")
      HrLite.config.leadership_emails = [ "lead@x.test" ]
      travel_to(1.day.from_now) do
        expect(kudo.deletable_by?(admin)).to be(true)
        expect(kudo.deletable_by?(leader)).to be(true)
        expect(kudo.deletable_by?(create(:user))).to be(false)
        expect(kudo.deletable_by?(nil)).to be(false)
      end
    end
  end

  describe "#badge_label" do
    it "maps the badge key" do
      expect(build(:kudo, badge: "problem_solver").badge_label).to eq("Problem solver")
      expect(build(:kudo, badge: nil).badge_label).to be_nil
    end
  end

  describe "#register_mentions!" do
    let(:giver) { create(:user, name: "Giver") }
    let(:asha) { create(:user, name: "Asha") }
    let(:dev) { create(:user, name: "Dev") }
    let(:bells) { [] }

    before { HrLite.config.notify = ->(**kw) { bells << kw } }

    it "creates mention rows for existing users, excluding the giver and unknown ids" do
      kudo = create(:kudo, giver: giver,
                    message: "Nice @[Asha](#{asha.id}) @[Dev](#{dev.id}) @[Ghost](99999) @[Self](#{giver.id})")
      kudo.register_mentions!

      expect(kudo.mentioned_users).to contain_exactly(asha, dev)
    end

    it "notifies mentioned users with a marker-free body" do
      kudo = create(:kudo, giver: giver, message: "Bravo @[Asha](#{asha.id})")
      expect { kudo.register_mentions! }
        .to have_enqueued_mail(HrLite::EventMailer, :event).once

      bell = bells.find { |b| b[:user] == asha }
      expect(bell[:title]).to eq("Giver gave you kudos")
      expect(bell[:body]).to include("@Asha")
      expect(bell[:body]).not_to include("](")
    end
  end

  describe "cascade" do
    it "deletes mentions with the kudo" do
      user = create(:user)
      kudo = create(:kudo, message: "Hi @[U](#{user.id})")
      kudo.register_mentions!
      expect { kudo.destroy! }.to change(HrLite::KudoMention, :count).by(-1)
    end
  end
end
