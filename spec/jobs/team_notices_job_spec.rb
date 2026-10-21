require "rails_helper"

RSpec.describe HrLite::TeamNoticesJob do
  let(:today) { Date.new(2027, 7, 8) }
  let(:type) { create(:leave_type, name: "Sick leave") }

  around { |example| travel_to(today.in_time_zone.change(hour: 10)) { example.run } }


  it "sends nothing when nobody is on leave and nobody has a birthday" do
    create(:user)
    expect { described_class.perform_now }.not_to have_enqueued_mail(HrLite::EventMailer, :event)
  end

  it "emails every current employee who is out today, pending included, and whose birthday it is" do
    create(:leave_request, user: create(:user, name: "Asha"), leave_type: type, start_date: today - 1, end_date: today + 1)
    create(:leave_request, user: create(:user, name: "Ravi"), leave_type: type, start_date: today, end_date: today,
                           status: "rejected")
    create(:employee_profile, user: create(:user, name: "Mia"), date_of_birth: Date.new(1990, 7, 8))
    sent = []
    allow(HrLite::EventMailer).to receive(:event) do |**kw|
      sent << kw
      instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    end

    described_class.perform_now

    leave = sent.select { |m| m[:subject].start_with?("On leave today") }
    expect(leave.size).to eq(HrLite.active_employees.size)
    expect(leave.first[:lines]).to eq([ "Asha — 07 Jul – 09 Jul (pending approval)" ])
    expect(sent.find { |m| m[:subject].start_with?("Birthdays today") }[:lines]).to eq([ "Happy birthday, Mia" ])
  end
end
