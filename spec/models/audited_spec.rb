require "rails_helper"

# Exercises the Audited concern through a real audited model once one exists;
# until the attendance phase lands, a throwaway audited model on the kudos
# table stands in.
RSpec.describe HrLite::Audited do
  before(:all) do
    unless HrLite.const_defined?(:AuditedProbe)
      HrLite.const_set(:AuditedProbe, Class.new(HrLite::ApplicationRecord) do
        self.table_name = "hr_lite_kudos"
        include HrLite::Audited

        def self.name = "HrLite::AuditedProbe"
      end)
    end

    unless HrLite.const_defined?(:EncryptedProbe)
      HrLite.const_set(:EncryptedProbe, Class.new(HrLite::ApplicationRecord) do
        self.table_name = "hr_lite_kudos"
        encrypts :message
        include HrLite::Audited

        def self.name = "HrLite::EncryptedProbe"
      end)
    end
  end

  after(:all) do
    HrLite.send(:remove_const, :AuditedProbe) if HrLite.const_defined?(:AuditedProbe)
    HrLite.send(:remove_const, :EncryptedProbe) if HrLite.const_defined?(:EncryptedProbe)
  end

  let(:actor) { create(:user, name: "Boss") }
  let(:probe) { HrLite::AuditedProbe.create!(giver_id: actor.id, message: "policy") }

  before do
    HrLite::Current.actor = actor
    HrLite.config.leadership_emails = [ "lead@x.test" ]
  end

  after { HrLite::Current.reset }

  it "logs creates with the actor and publishes policy.changed" do
    expect { probe }.to change(HrLite::AuditLog, :count).by(1)
      .and have_enqueued_mail(HrLite::EventMailer, :leadership).once

    log = HrLite::AuditLog.last
    expect(log.actor).to eq(actor)
    expect(log.action).to eq("create")
    expect(log.subject_type).to eq("HrLite::AuditedProbe")
    expect(log.audited_changes).to include("message")
  end

  it "logs updates with old/new pairs, skipping timestamps" do
    probe
    expect { probe.update!(message: "new policy") }.to change(HrLite::AuditLog, :count).by(1)

    log = HrLite::AuditLog.last
    expect(log.action).to eq("update")
    expect(log.audited_changes).to eq("message" => [ "policy", "new policy" ])
  end

  it "skips no-op updates" do
    probe
    expect { probe.touch }.not_to change(HrLite::AuditLog, :count)
  end

  it "logs destroys with a label" do
    probe
    expect { probe.destroy! }.to change(HrLite::AuditLog, :count).by(1)
    expect(HrLite::AuditLog.last.audited_changes).to include("_destroyed")
  end

  it "redacts encrypted attributes — plaintext never reaches the trail" do
    record = HrLite::EncryptedProbe.create!(giver_id: actor.id, message: "PAN ABCDE1234F")
    record.update!(message: "PAN ZZZZZ9999Z")

    log = HrLite::AuditLog.last
    expect(log.audited_changes["message"]).to eq(HrLite::Audited::REDACTED)
    expect(log.audited_changes.to_s).not_to include("ABCDE1234F", "ZZZZZ9999Z")
  end

  it "never breaks the domain write when auditing fails" do
    allow(HrLite::AuditLog).to receive(:create!).and_raise("db hiccup")
    expect { probe }.not_to raise_error
  end

  describe "audit log immutability" do
    it "refuses updates to persisted rows" do
      probe
      log = HrLite::AuditLog.last
      expect { log.update!(action: "tampered") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
