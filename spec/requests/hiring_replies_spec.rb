require "rails_helper"

RSpec.describe "Hiring reply page", type: :request, no_legacy_bridge: true do
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Khushboo") }
  let(:campaign) { HrLite::HiringCampaign.create!(title: "Drive", position: "Sales Intern", stipend: "₹15,000") }
  let(:candidate) { campaign.candidates.create!(name: "Asha Rao", email: "asha@x.in", stage: "invited") }
  let(:day) { HrLite::HiringCandidate.reply_dates.first }

  before { Rails.cache.clear }

  def reply(**params)
    post "/hr/apply/#{candidate.interest_token}", params: { interested: "yes", date: day.iso8601, slot: "10-12", joining: "two_weeks",
                                                            stipend_ok: "yes", location_ok: "yes", schedule_ok: "no", programme_ok: "yes", **params }
  end

  it "needs no login, takes one reply, moves the candidate and tells the HR person who emailed them" do
    template = HrLite::HiringTemplate.create!(name: "T", subject: "S", body: "B")
    HrLite::HiringMessage.create!(candidate: candidate, template: template, batch: "b", status: "sent", sent_at: 1.hour.ago, sent_by: hr)
    bells = []
    HrLite.config.notify = ->(**args) { bells << args }

    get "/hr/apply/#{candidate.interest_token}"
    expect(response.body).to include("Hi Asha", "Sales Intern", "monthly stipend of ₹15,000", "10 AM – 12 PM")
    reply
    expect(response).to redirect_to("/hr/apply/#{candidate.interest_token}")
    candidate.reload
    expect([ candidate.stage, candidate.preferred_date, candidate.preferred_slot, candidate.answers["schedule_ok"] ]).to eq([ "interested", day, "10-12", "no" ])
    expect(candidate.timeline.pluck(:action)).to include("hiring.replied", "hiring.stage")
    expect(bells.sole).to include(user: hr, kind: "hiring.reply", title: "Asha Rao replied: interested", path: "/admin/hiring_candidates/#{candidate.id}")

    get "/hr/apply/#{candidate.interest_token}"
    expect(response.body).to include("Thanks, we have your answers")
    reply
    expect(response.body).to include("You have already replied")

    sign_in hr
    get "/hr/admin/hiring_candidates/#{candidate.id}"
    expect(response.body).to include("Their reply", "Within 2 weeks", %(value="#{day.iso8601}"), 'value="10:00"', "Call to confirm")
    get "/hr/admin/hiring_campaigns/#{campaign.id}", params: { replied: "1" }
    expect(response.body).to include("Asha Rao")
  end

  it "takes a no without a slot, and explains a missing or full answer" do
    3.times { |i| campaign.candidates.create!(name: "C#{i}", email: "c#{i}@x.in", preferred_date: day, preferred_slot: "2-4") }
    campaign.candidates.create!(name: "C9", email: "c9@x.in", preferred_date: day, preferred_slot: "2-4")
    reply(interested: "")
    expect(response.body).to include("Tell us whether you want to go ahead")
    reply(date: "2020-01-01")
    expect(response.body).to include("Pick a day for the interview")
    reply(slot: "1-3")
    expect(response.body).to include("Pick a time slot")
    reply(slot: "2-4")
    expect(response.body).to include("That slot just filled up")
    reply(joining: "")
    expect(response.body).to include("Tell us how soon you can join")
    reply(interested: "no")
    expect(candidate.reload.slice(:stage, :preferred_slot).values).to eq([ "not_interested", nil ])
  end

  it "refuses an unknown token and limits tries" do
    get "/hr/apply/nope"
    expect(response).to have_http_status(:not_found)
    11.times { reply(interested: "") }
    expect(flash[:alert]).to eq("Too many tries. Please try again in an hour.")
  end

  it "fills @interest_link with the candidate's own page" do
    HrLite.config.public_url_base = "https://hr.example.com"
    mail = HrLite::HiringMerge.new(candidate, sender_name: "K").render(HrLite::HiringTemplate.new(subject: "S", body: "Reply: @interest_link"))
    expect(mail.body).to eq("Reply: https://hr.example.com/apply/#{candidate.interest_token}")
  end
end
