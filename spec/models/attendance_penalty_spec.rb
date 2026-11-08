require "rails_helper"

RSpec.describe HrLite::AttendancePenalty do
  let(:user) { create(:user) }
  let(:record) { create(:attendance_record, user: user, date: Date.current - 1) }
  let(:penalty) do
    described_class.create!(user_id: user.id, attendance_record: record, date: record.date, minutes: 60, reason: "late")
  end

  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  it "logs a system-created penalty but tells leadership nothing, so a late check-in stays fast" do
    expect { penalty }.not_to have_enqueued_mail(HrLite::EventMailer, :leadership)
    expect(HrLite::AuditLog.where(subject: penalty, action: "create")).to exist
  end

  it "still tells leadership when HR removes one" do
    penalty
    expect { penalty.update!(removed_at: Time.current, removal_reason: "Traffic") }
      .to have_enqueued_mail(HrLite::EventMailer, :leadership).once
  end
end
