require "rails_helper"

RSpec.describe "Hiring reply pages", type: :request, no_legacy_bridge: true do
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Khushboo") }
  let(:campaign) { HrLite::HiringCampaign.create!(title: "Drive", position: "Sales Intern", stipend: "₹15,000") }
  let(:candidate) { campaign.candidates.create!(name: "Asha Rao", email: "asha@x.in", stage: "invited") }
  let(:round1) { candidate.reply_for(1) }
  let(:day) { HrLite::HiringReply.dates(allow_sunday: false).first }
  let(:pdf) { Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\n%âãÏÓ\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n"), "application/pdf", original_filename: "cv.pdf") }
  let(:svg) { Rack::Test::UploadedFile.new(StringIO.new("<svg xmlns='http://www.w3.org/2000/svg'></svg>"), "application/pdf", original_filename: "id.pdf") }

  before { Rails.cache.clear }

  def reply(token = round1.token, **params)
    post "/hr/apply/#{token}", params: { interested: "yes", date: day.iso8601, slot: "10-12", joining: "two_weeks", alternate_phone: "+91 98765 43210",
                                         stipend_ok: "yes", location_ok: "yes", schedule_ok: "no", programme_ok: "yes", **params }
  end

  it "takes round 1 without a login, moves the candidate and tells the HR person who emailed them" do
    template = HrLite::HiringTemplate.create!(name: "T", subject: "S", body: "B")
    HrLite::HiringMessage.create!(candidate: candidate, template: template, batch: "b", status: "sent", sent_at: 1.hour.ago, sent_by: hr)
    bells = []
    HrLite.config.notify = ->(**args) { bells << args }

    get "/hr/apply/#{round1.token}"
    expect(response.body).to include("Hi Asha", "monthly stipend of ₹15,000", "10 AM – 12 PM", "Alternate phone")
    reply
    expect(response).to redirect_to("/hr/apply/#{round1.token}")
    round1.reload
    expect([ candidate.reload.stage, round1.preferred_date, round1.preferred_slot, round1.answers["schedule_ok"], round1.alternate_phone ])
      .to eq([ "interested", day, "10-12", "no", "+91 98765 43210" ])
    expect(candidate.timeline.pluck(:action)).to include("hiring.replied", "hiring.stage")
    expect(bells.sole).to include(user: hr, title: "Asha Rao replied to round 1: interested", path: "/admin/hiring_candidates/#{candidate.id}")

    get "/hr/apply/#{round1.token}"
    expect(response.body).to include("Thanks, we have your answers")
    reply
    expect(response.body).to include("You have already replied")
  end

  it "asks round 2 for documents, checking what the files really are" do
    candidate.update!(stage: "interview", round: 1)
    round2 = candidate.reply_for(2)
    get "/hr/apply/#{round2.token}"
    expect(response.body).to include("round 2", "CV", "Photo ID")
    expect(response.body).not_to include("How soon can you join")

    reply(round2.token, documents: { cv: pdf })
    expect(response.body).to include("Attach your Photo ID")
    reply(round2.token, documents: { cv: pdf, photo_id: svg })
    expect(response.body).to include("Photo ID must be a PDF, JPG or PNG")
    stub_const("HrLite::HiringReply::DOCUMENT_MAX", 10)
    reply(round2.token, documents: { cv: pdf, photo_id: pdf })
    expect(response.body).to include("CV must be 5 MB or smaller")
    stub_const("HrLite::HiringReply::DOCUMENT_MAX", 5.megabytes)
    reply(round2.token, documents: { cv: pdf, photo_id: pdf })
    expect(round2.reload.documents.map { |d| round2.document_label(d) }).to eq([ "CV", "Photo ID" ])
    expect(candidate.reload.stage).to eq("interview")

    sign_in hr
    get "/hr/admin/hiring_candidates/#{candidate.id}"
    expect(response.body).to include("Round 2 reply", "Photo ID", %(value="#{day.iso8601}"), 'value="10:00"', "Call to confirm")
    blob = round2.documents.first
    expect(blob.download).not_to start_with("%PDF") # stored as ciphertext
    get "/hr/admin/hiring_candidates/#{candidate.id}/document", params: { attachment_id: blob.id }
    expect([ response.body.b, response.media_type ]).to eq([ pdf.tap(&:rewind).read.b, "application/pdf" ])
    expect(response.headers["Content-Disposition"]).to include("attachment", "cv.pdf")
    expect(response.body).not_to include("rails/active_storage")
    expect(HrLite::AuditLog.where(action: "hiring.document_viewed").count).to eq(1)
    get "/hr/admin/hiring_candidates/#{candidate.id}/document", params: { attachment_id: 0 }
    expect(response).to have_http_status(:not_found)
    get "/hr/admin/hiring_campaigns/#{campaign.id}", params: { round: 2 }
    expect(response.body).to include("Asha Rao", "Booked round 2")
  end

  it "keeps Sunday off unless the campaign allows it" do
    monday = Date.new(2026, 10, 26)
    expect(HrLite::HiringReply.dates(allow_sunday: false, from: monday).none?(&:sunday?)).to be(true)
    expect(HrLite::HiringReply.dates(allow_sunday: true, from: monday)).to include(Date.new(2026, 11, 1))
    sunday = HrLite::HiringReply.dates(allow_sunday: true).find(&:sunday?)
    reply(date: sunday.iso8601)
    expect(response.body).to include("Pick a day for the interview")
    campaign.update!(allow_sunday: true)
    reply(date: sunday.iso8601)
    expect(round1.reload.preferred_date).to eq(sunday)
  end

  it "takes a no without a slot, and explains a missing or full answer" do
    others = Array.new(4) { |i| campaign.candidates.create!(name: "C#{i}", email: "c#{i}@x.in").reply_for(1) }
    others.each { |r| r.update!(responded_at: Time.current, preferred_date: day, preferred_slot: "2-4") }
    reply(interested: "")
    expect(response.body).to include("Tell us whether you want to go ahead")
    reply(slot: "1-3")
    expect(response.body).to include("Pick a time slot")
    reply(slot: "2-4")
    expect(response.body).to include("That slot just filled up")
    reply(joining: "")
    expect(response.body).to include("Tell us how soon you can join")
    reply(alternate_phone: "call me")
    expect(response.body).to include("That phone number does not look right")
    reply(interested: "no")
    expect([ candidate.reload.stage, round1.reload.preferred_slot ]).to eq([ "not_interested", nil ])
  end

  it "refuses an unknown token and limits tries" do
    get "/hr/apply/nope"
    expect(response).to have_http_status(:not_found)
    11.times { reply(interested: "") }
    expect(flash[:alert]).to eq("Too many tries. Please try again in an hour.")
  end

  it "fills each round's link only when a template names it" do
    HrLite.config.public_url_base = "https://hr.example.com"
    render = ->(body) { HrLite::HiringMerge.new(candidate, sender_name: "K").render(HrLite::HiringTemplate.new(subject: "S", body: body)).body }
    expect(render.("Hi")).to eq("Hi")
    expect(candidate.replies).to be_empty
    expect(render.("Round 3: @round3_link")).to eq("Round 3: https://hr.example.com/apply/#{candidate.reply_for(3).token}")
    expect(candidate.replies.pluck(:round)).to eq([ 3 ])
  end

  describe "round 3 joining details" do
    # A made-up Aadhaar with a valid Verhoeff check digit; never a real one.
    let(:aadhaar) { "23456789012".then { |base| (0..9).map { |d| "#{base}#{d}" }.find { |n| HrLite::HiringReply.aadhaar_valid?(n) } } }
    let(:round3) { candidate.reply_for(3) }

    def kyc(**params)
      reply(round3.token, aadhaar_number: aadhaar, pan_number: "abcde1234f", consent: "1",
                          documents: { marksheets: pdf, aadhaar: pdf, pan: pdf, salary_slip_1: pdf, salary_slip_2: pdf, salary_slip_3: pdf }, **params)
    end

    it "takes Aadhaar, PAN and salary slips encrypted, and shows HR only masked numbers until an audited reveal" do
      get "/hr/apply/#{round3.token}"
      expect(response.body).to include("Aadhaar number", "I don't have a PAN yet", "I have no salary slips", "I agree to share")
      expect(response.body).not_to include("Address proof")
      kyc(consent: "")
      expect(response.body).to include("Tick the consent box")
      kyc(aadhaar_number: "123456789012")
      expect(response.body).to include("That Aadhaar number does not look right")
      expect(response.body).not_to include("123456789012")
      kyc(pan_number: "12345")
      expect(response.body).to include("That PAN does not look right")
      kyc
      round3.reload
      expect([ round3.aadhaar_number, round3.pan_number, round3.documents.count ]).to eq([ aadhaar, "ABCDE1234F", 6 ])
      raw = HrLite::HiringReply.connection.select_one("SELECT aadhaar_number, pan_number FROM hr_lite_hiring_replies WHERE id = #{round3.id}")
      expect(raw.values.join).not_to include(aadhaar)
      expect(raw.values.join).not_to include("ABCDE1234F")

      sign_in hr
      get "/hr/admin/hiring_candidates/#{candidate.id}"
      expect(response.body).to include("XXXX XXXX #{aadhaar.last(4)}", "XXXXX1234X", "Show full Aadhaar")
      expect(response.body).not_to include(aadhaar)
      post "/hr/admin/hiring_candidates/#{candidate.id}/reveal", params: { reply_id: round3.id, field: "aadhaar" }
      expect(response.body).to include(aadhaar)
      expect(HrLite::AuditLog.where(action: "hiring.kyc_revealed").sole.audited_changes).to eq("field" => "aadhaar", "round" => 3)
      post "/hr/admin/hiring_candidates/#{candidate.id}/reveal", params: { reply_id: round3.id, field: "nope" }
      expect(response).to have_http_status(:not_found)
    end

    it "lets a candidate without a PAN or salary slips go ahead, and tells HR" do
      reply(round3.token, aadhaar_number: aadhaar, pan_pending: "1", no_salary_slips: "1", consent: "1", documents: { marksheets: pdf, aadhaar: pdf })
      round3.reload
      expect([ round3.pan_pending, round3.no_salary_slips, round3.pan_number, round3.documents.count ]).to eq([ true, true, nil, 2 ])
      sign_in hr
      get "/hr/admin/hiring_candidates/#{candidate.id}"
      expect(response.body).to include("PAN pending: collect at joining", "None (fresher)")
    end
  end
end
