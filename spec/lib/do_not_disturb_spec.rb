require "rails_helper"

RSpec.describe "Do not disturb" do
  include ActiveJob::TestHelper

  let(:asha) { create(:user, name: "Asha") }
  let(:now) { Time.zone.local(2026, 10, 20, 11, 0) }

  before do
    HrLite.config.office_geofence = true
    travel_to(now)
  end

  after { travel_back }

  def publish = HrLite::Notifications.publish("leave.approved", title: "Leave approved", bell_to: [ asha ], email_to: [ asha ])

  it "holds HR emails until a Busy or Meeting ends, but still drops the bell" do
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "busy", source: "employee", ends_at: now + 45.minutes)
    expect(HrLite).to receive(:notify).with(hash_including(user: asha))
    publish
    expect(ActionMailer::MailDeliveryJob).to have_been_enqueued.at(now + 45.minutes)
  end

  it "sends straight away when the person is reachable or on a break" do
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "lunch", source: "employee", ends_at: now + 30.minutes)
    publish
    mails = enqueued_jobs.select { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" }
    expect(mails.size).to eq(1)
    expect(mails.first["scheduled_at"]).to be_nil
  end

  it "ignores a Busy that has already run out" do
    HrLite::WorkModeEvent.create!(user_id: asha.id, mode: "busy", source: "employee", started_at: now - 1.hour, ends_at: now - 1.minute)
    expect(HrLite::WorkStatus.do_not_disturb_until(asha.id)).to be_nil
  end
end
