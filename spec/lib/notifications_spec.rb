require "rails_helper"

RSpec.describe HrLite::Notifications do
  let(:user_a) { create(:user, email: "a@x.test") }
  let(:user_b) { create(:user, email: "b@x.test") }
  let(:bells) { [] }

  before do
    HrLite.config.notify = ->(**kw) { bells << kw }
    HrLite.config.leadership_emails = [ "lead1@x.test", "lead2@x.test" ]
  end

  describe ".publish" do
    it "warns and no-ops for unknown events" do
      expect(Rails.logger).to receive(:warn).with(/unknown notification event nope/)
      described_class.publish("nope", title: "T")
      expect(bells).to be_empty
    end

    it "fans out bells to bell_to for bell-enabled events" do
      described_class.publish("leave.requested", title: "T", body: "B", path: "/p",
                              bell_to: [ user_a, user_a, nil ])
      kinds = bells.map { |b| b[:kind] }
      expect(kinds).to include("leave.requested")
      expect(bells.count { |b| b[:user] == user_a }).to eq(1)
    end

    it "emails each email_to user for email-enabled events" do
      expect {
        described_class.publish("kudos.mentioned", title: "T", email_to: [ user_a, user_b ])
      }.to have_enqueued_mail(HrLite::EventMailer, :event).twice
    end

    it "skips users without email addresses" do
      user_a.update!(email: "")
      expect {
        described_class.publish("kudos.mentioned", title: "T", email_to: [ user_a ])
      }.not_to have_enqueued_mail(HrLite::EventMailer, :event)
    end

    it "sends ONE leadership email to all configured addresses" do
      expect {
        described_class.publish("policy.changed", title: "T", diff: { "x" => [ 1, 2 ] })
      }.to have_enqueued_mail(HrLite::EventMailer, :leadership).once
    end

    it "skips leadership email when none configured" do
      HrLite.config.leadership_emails = []
      expect {
        described_class.publish("policy.changed", title: "T")
      }.not_to have_enqueued_mail(HrLite::EventMailer, :leadership)
    end

    it "bells leadership users resolvable by email, skipping bell_to duplicates" do
      leader = create(:user, email: "lead1@x.test")
      leader2 = create(:user, email: "lead2@x.test")
      described_class.publish("leave.requested", title: "T", bell_to: [ leader ])

      expect(bells.count { |b| b[:user].id == leader.id }).to eq(1)
      expect(bells.count { |b| b[:user].id == leader2.id }).to eq(1)
    end

    it "honours a host-overridden matrix row" do
      HrLite.config.notification_matrix = described_class::DEFAULT_MATRIX.merge(
        "kudos.mentioned" => { bell: false, email: false, leadership_email: false, leadership_bell: false }
      )
      expect {
        described_class.publish("kudos.mentioned", title: "T", bell_to: [ user_a ], email_to: [ user_a ])
      }.not_to have_enqueued_mail(HrLite::EventMailer, :event)
      expect(bells).to be_empty
    end

    it "swallows channel failures without breaking the publish" do
      allow(HrLite::EventMailer).to receive(:leadership).and_raise("smtp down")
      expect {
        described_class.publish("policy.changed", title: "T")
      }.not_to raise_error
    end

    it "swallows per-user email failures" do
      allow(HrLite::EventMailer).to receive(:event).and_raise("smtp down")
      expect {
        described_class.publish("kudos.mentioned", title: "T", email_to: [ user_a ])
      }.not_to raise_error
    end

    it "swallows leadership-bell resolution failures" do
      allow(HrLite).to receive(:leadership_users).and_raise("db down")
      expect {
        described_class.publish("leave.requested", title: "T", bell_to: [ user_a ])
      }.not_to raise_error
    end
  end
end
