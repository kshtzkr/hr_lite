require "rails_helper"

RSpec.describe HrLite::DailyDigestJob do
  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  it "sends nothing on a quiet day" do
    expect { described_class.perform_now }.not_to have_enqueued_mail(HrLite::EventMailer, :leadership)
  end

  it "compiles out-today, pending, flagged and missing-checkout lines" do
    travel_to(Date.new(2027, 7, 6)) do
      user = create(:user, name: "Asha")
      type = create(:leave_type, name: "Casual", annual_quota: 12)
      create(:leave_request, :approved, user: user, leave_type: type,
             start_date: Date.new(2027, 7, 6), end_date: Date.new(2027, 7, 6))
      create(:leave_request, user: create(:user, name: "Dev"), leave_type: type,
             start_date: Date.new(2027, 7, 8), end_date: Date.new(2027, 7, 8))
      create(:attendance_record, :checked_in, :flagged, user: create(:user, name: "Zed"), date: Date.new(2027, 7, 6))
      create(:attendance_record, user: create(:user, name: "Mia"), date: Date.new(2027, 7, 5),
             check_in_at: Time.zone.parse("2027-07-05 09:00"))

      captured = nil
      allow(HrLite::EventMailer).to receive(:leadership) do |**kw|
        captured = kw
        instance_double(ActionMailer::MessageDelivery, deliver_later: true)
      end

      described_class.perform_now

      expect(captured).not_to be_nil
      lines = captured[:lines].join("\n")
      expect(lines).to include("On leave: Asha")
        .and include("Pending approval: Dev")
        .and include("Flagged punch: Zed")
        .and include("Missing checkout yesterday: Mia")
    end
  end
end
