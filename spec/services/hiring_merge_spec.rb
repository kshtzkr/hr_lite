require "rails_helper"

RSpec.describe HrLite::HiringMerge do
  let(:campaign) { HrLite::HiringCampaign.create!(title: "Drive", position: "Sales Intern", stipend: "₹15,000", location: "Noida") }
  let(:candidate) { campaign.candidates.create!(name: "Asha Rao", email: "a@x.in", course: "BBA", extra: { "native_state" => "UP", "position" => "hacked" }) }

  def render(subject, body) = described_class.new(candidate, sender_name: "Khushboo").render(HrLite::HiringTemplate.new(subject: subject, body: body))

  it "fills campaign, candidate, sheet and sender fields, reserved names first" do
    mail = render("@position at escapes.asia", "Hi @first_name from @native_state, @stipend in @location. Mail khushboo@earthlygroup.in. @sender_name")
    expect(mail.subject).to eq("Sales Intern at escapes.asia")
    expect(mail.body).to eq("Hi Asha from UP, ₹15,000 in Noida. Mail khushboo@earthlygroup.in. Khushboo")
    expect(mail.missing).to be_empty
  end

  it "reports empty and unknown fields instead of sending blanks" do
    mail = render("Hi", "@branch @ctc @nope @nope")
    expect(mail.missing).to eq([ "@branch (empty)", "@ctc (empty)", "@nope (unknown)" ])
    expect(mail.body).to eq("@branch @ctc @nope @nope")
  end

  it "fills the interview fields from the latest scheduled round" do
    candidate.interviews.create!(round: 1, starts_at: Time.find_zone("Asia/Kolkata").parse("2026-11-03 11:30"), ends_at: Time.find_zone("Asia/Kolkata").parse("2026-11-03 12:00"),
                                 status: "scheduled", meet_link: "https://meet.google.com/abc")
    expect(render("x", "@interview_date @interview_time @meet_link").body).to eq("3 November 2026 11:30 AM https://meet.google.com/abc")
  end
end
