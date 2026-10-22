require "rails_helper"

RSpec.describe "Hiring", type: :request, no_legacy_bridge: true do
  include ActiveJob::TestHelper

  # Stands in for the host's Gmail + Calendar adapter.
  let(:adapter) do
    Class.new do
      attr_reader :sent, :events
      attr_accessor :ready, :fail_with

      def initialize = (@sent, @events, @ready = [], [], true)
      def sender = { ready: ready, email: "hire@x.in", name: "Khushboo", connect_url: "/connect" }

      def send_email(**mail)
        raise fail_with, "Gmail answered 500" if fail_with

        @sent << mail
        { message_id: "m#{@sent.size}", thread_id: "t#{@sent.size}" }
      end

      def create_event(**event)
        raise fail_with, "Calendar answered 503" if fail_with

        @events << [ :create, event ]
        { event_id: "e#{@events.size}", meet_link: "https://meet.google.com/x" }
      end

      def update_event(**event) = (raise(fail_with, "nope") if fail_with) || @events << [ :update, event ]
      attr_accessor :draft

      def draft_email(text:, placeholders:)
        raise fail_with, "model refused" if fail_with

        @drafted = [ text, placeholders ]
        draft || { name: "Interest check (AI)", subject: "@position at escapes.asia", body: "Hi @first_name,\n\nBest,\n@sender_name" }
      end
      attr_reader :drafted

      def signature = "<b>Khushboo</b><script>x()</script> | escapes.asia"

      def cancel_event(**event) = (raise(fail_with, "nope") if fail_with) || @events << [ :cancel, event ]
    end.new
  end
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Khushboo") }
  let(:campaign) { HrLite::HiringCampaign.create!(title: "October drive", position: "Sales Intern", stipend: "₹15,000") }
  let(:template) { HrLite::HiringTemplate.find_by!(name: "Interest check") }

  before do
    Rails.cache.clear # the send rate limit counts in the cache
    HrLite.config.hiring = adapter
    sign_in hr
  end

  def candidate(name = "Asha", **attributes) = campaign.candidates.create!(name: name, email: "#{name.downcase}@x.in", **attributes)

  it "keeps everyone without hiring.manage out" do
    sign_in user_with_roles(HrLite::Role::EMPLOYEE)
    get "/hr/admin/hiring_campaigns"
    expect(response).to redirect_to("/hr/")
  end

  it "creates a campaign that starts from the last offer, and edits it" do
    get "/hr/admin/hiring_campaigns"
    expect(response.body).to include("No campaigns yet")
    post "/hr/admin/hiring_campaigns", params: { hiring_campaign: { title: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
    post "/hr/admin/hiring_campaigns", params: { hiring_campaign: { title: "Drive", position: "Ops Intern", stipend: "₹15,000" } }
    created = HrLite::HiringCampaign.sole
    expect(response).to redirect_to("/hr/admin/hiring_campaigns/#{created.id}")

    get "/hr/admin/hiring_campaigns/new"
    expect(response.body).to include("Ops Intern", "₹15,000")
    patch "/hr/admin/hiring_campaigns/#{created.id}", params: { hiring_campaign: { position: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
    patch "/hr/admin/hiring_campaigns/#{created.id}", params: { hiring_campaign: { status: "closed" } }
    get "/hr/admin/hiring_campaigns/#{created.id}/edit"
    get "/hr/admin/hiring_campaigns"
    expect(response.body).to include("Closed")
  end

  describe "importing a sheet" do
    def upload(csv, name = "list.csv") = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: name)

    it "previews without saving, then imports on confirm" do
      get "/hr/admin/hiring_campaigns/#{campaign.id}/import"
      post "/hr/admin/hiring_campaigns/#{campaign.id}/import", params: { sheet: upload("Student Name,EMAIL ID.,Native State\nAsha,a@x.in,UP\n,b@x.in,\n") }
      expect(response.body).to include("Native State", "Extra: @native_state", "Row 3: no name", "Import 1 candidates")
      expect(campaign.candidates).to be_empty

      sealed = response.body[/name="rows" value="([^"]+)"/, 1]
      post "/hr/admin/hiring_campaigns/#{campaign.id}/import", params: { rows: CGI.unescapeHTML(sealed), confirm: "1" }
      expect(flash[:notice]).to eq("1 added, 0 updated, 1 skipped.")
      expect(campaign.candidates.sole.extra).to eq("native_state" => "UP")
      get "/hr/admin/hiring_candidates/#{campaign.candidates.sole.id}"
      expect(response.body).to include("Imported", "Native state")
    end

    it "asks HR to pick between two phone columns" do
      post "/hr/admin/hiring_campaigns/#{campaign.id}/import", params: { sheet: upload("Name,Email,Phone,Mobile\nA,a@x.in,1,2\n") }
      expect(response.body).to include("Pick one column for each field")
      expect(response.body).not_to include("Import 1 candidates")
    end

    it "refuses a file it cannot read, an expired preview and a race" do
      post "/hr/admin/hiring_campaigns/#{campaign.id}/import", params: { sheet: upload("x", "list.xlsx") }
      expect(flash[:alert]).to eq("Upload the sheet as a .csv file.")
      HrLite.config.read_sheet = ->(*) { raise IOError }
      post "/hr/admin/hiring_campaigns/#{campaign.id}/import", params: { sheet: upload("x") }
      expect(flash[:alert]).to start_with("That file could not be read")
      post "/hr/admin/hiring_campaigns/#{campaign.id}/import", params: { rows: "tampered" }
      expect(flash[:alert]).to eq("That preview expired. Upload the sheet again.")

      HrLite.config.read_sheet = ->(*) { [ %w[Name Email], %w[A a@x.in] ] }
      allow_any_instance_of(HrLite::HiringImport).to receive(:import!).and_raise(ActiveRecord::RecordNotUnique)
      post "/hr/admin/hiring_campaigns/#{campaign.id}/import", params: { sheet: upload("x"), confirm: "1" }
      expect(flash[:alert]).to start_with("Another import ran")
    end
  end

  describe "bulk email" do
    let!(:asha) { candidate("Asha") }
    let!(:bina) { candidate("Bina") }

    it "shows who is left out and why, then sends once per candidate" do
      template.update!(body: "Hi @first_name, @stipend. @branch")
      bina.update!(branch: "Finance")
      asha.update!(branch: "Sales")
      HrLite::HiringMessage.create!(candidate: asha, template: template, batch: "old", status: "sent")
      campaign.candidates.create!(name: "Chen", email: "chen@x.in")

      get "/hr/admin/hiring_campaigns/#{campaign.id}"
      expect(response.body).to include("Asha", "Bina", "Chen", "Review email", 'data-hrl-select-all="candidate_ids[]"')
      get "/hr/admin/hiring_campaigns/#{campaign.id}/send/new", params: { template_id: template.id, all: "1" }
      expect(response.body).to include("to 1 candidate", "Asha</strong>: already sent this template", "Chen</strong>: @branch (empty)", "hire@x.in")

      perform_enqueued_jobs do
        2.times { post "/hr/admin/hiring_campaigns/#{campaign.id}/send", params: { template_id: template.id, candidate_ids: [ bina.id ] } }
      end
      expect(adapter.sent).to eq([ { to: "bina@x.in", subject: "Sales Intern at escapes.asia: please confirm your interest", body: "Hi Bina, ₹15,000. Finance" } ])
      message = bina.messages.sole
      expect([ message.status, message.gmail_message_id, message.gmail_thread_id, message.sent_by ]).to eq([ "sent", "m1", "t1", hr ])
      expect(bina.reload.stage).to eq("invited")
      get "/hr/admin/hiring_candidates/#{bina.id}"
      expect(response.body).to include("Email sent: Interest check", "Moved to Invited")
      expect(HrLite::AuditLog.find_by(action: "hiring.batch").audited_changes).to include("recipients" => 1)

      HrLite::HiringSendJob.perform_now(message.id) # a redelivered job
      expect(adapter.sent.size).to eq(1)
    end

    it "marks an unconfirmed send for a person to check and retries only a definite failure" do
      template.update!(body: "Hi @first_name")
      adapter.fail_with = HrLite::HiringDeliveryUnknown
      perform_enqueued_jobs { post "/hr/admin/hiring_campaigns/#{campaign.id}/send", params: { template_id: template.id, candidate_ids: [ asha.id ] } }
      unknown = asha.messages.sole
      expect(unknown.status).to eq("unknown")
      post "/hr/admin/hiring_messages/#{unknown.id}/retry"
      expect(unknown.reload.status).to eq("unknown")

      adapter.fail_with = HrLite::HiringDeliveryFailed
      perform_enqueued_jobs { post "/hr/admin/hiring_campaigns/#{campaign.id}/send", params: { template_id: template.id, candidate_ids: [ bina.id ] } }
      failed = bina.messages.sole
      expect([ failed.status, failed.error ]).to eq([ "failed", "Gmail answered 500" ])
      get "/hr/admin/hiring_campaigns/#{campaign.id}"
      expect(response.body).to include("Emails that need a look", "Send again", "check Gmail Sent")

      adapter.fail_with = nil
      perform_enqueued_jobs { post "/hr/admin/hiring_messages/#{failed.id}/retry" }
      expect(failed.reload.status).to eq("sent")
    end

    it "limits each person to ten sends an hour and ignores a row another click queued" do
      template.update!(body: "Hi @first_name")
      allow(HrLite::HiringMessage).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      10.times { post "/hr/admin/hiring_campaigns/#{campaign.id}/send", params: { template_id: template.id, candidate_ids: [ asha.id ] } }
      expect(flash[:notice]).to eq("0 emails queued from hire@x.in.")
      post "/hr/admin/hiring_campaigns/#{campaign.id}/send", params: { template_id: template.id, candidate_ids: [ asha.id ] }
      expect(flash[:alert]).to eq("Ten sends in an hour is the limit. Try again later.")
    end

    it "fails rather than sends when the template cannot be filled or no mailbox is ready" do
      message = HrLite::HiringMessage.create!(candidate: asha, template: HrLite::HiringTemplate.create!(name: "T", subject: "S", body: "@nope"), batch: "b")
      HrLite::HiringSendJob.perform_now(message.id)
      expect(message.reload.error).to eq("Missing @nope (unknown)")

      adapter.ready = false
      post "/hr/admin/hiring_campaigns/#{campaign.id}/send", params: { template_id: template.id, candidate_ids: [ bina.id ] }
      expect(flash[:alert]).to eq("Connect the hiring mailbox before sending.")
      get "/hr/admin/hiring_campaigns/#{campaign.id}"
      expect(response.body).to include("No hiring mailbox is connected", "Connect hire@x.in")
      other = HrLite::HiringMessage.create!(candidate: bina, template: template, batch: "b")
      HrLite::HiringSendJob.perform_now(other.id)
      expect(other.reload.error).to eq("No sender mailbox is connected")
    end
  end

  describe "stages and interviews" do
    let!(:asha) { candidate("Asha", stage: "invited") }

    def schedule(date: 2.days.from_now.to_date, time: "11:00", minutes: 45)
      post "/hr/admin/hiring_candidates/#{asha.id}/interviews", params: { date: date, time: time, minutes: minutes }
    end

    it "refuses moves the pipeline does not allow and needs a reason to reject" do
      schedule
      expect(flash[:alert]).to eq("Invited cannot be interviewed.")
      patch "/hr/admin/hiring_candidates/#{asha.id}/stage", params: { to: "selected" }
      expect(flash[:alert]).to eq("Invited cannot move to Selected.")
      patch "/hr/admin/hiring_candidates/#{asha.id}/stage", params: { to: "interview" }
      expect(flash[:alert]).to eq("That is not a decision HR makes here.")
      patch "/hr/admin/hiring_candidates/#{asha.id}/stage", params: { to: "interested" }
      expect(asha.reload.stage).to eq("interested")
      patch "/hr/admin/hiring_candidates/#{asha.id}/stage", params: { to: "rejected" }
      expect(flash[:alert]).to eq("Pick a rejection reason.")
      patch "/hr/admin/hiring_candidates/#{asha.id}/stage", params: { to: "rejected", reason: "Other" }
      expect(flash[:alert]).to eq("Write a note for “Other”.")
      patch "/hr/admin/hiring_candidates/#{asha.id}/stage", params: { to: "rejected", reason: "Stipend not acceptable", note: "Wants 25k" }
      expect(asha.reload.rejection_reason).to eq("Stipend not acceptable: Wants 25k")
      get "/hr/admin/hiring_candidates/#{asha.id}"
      expect(response.body).to include("Rejected because", "Moved to Rejected: Stipend not acceptable", "Khushboo")
    end

    it "schedules, reschedules and cancels rounds on the calendar, each round its own row" do
      asha.update!(stage: "interested")
      schedule(date: Date.yesterday)
      expect(flash[:alert]).to eq("Pick a date and time in the future.")
      schedule
      first = asha.interviews.sole
      expect([ first.round, first.status, first.event_id, (first.ends_at - first.starts_at) / 60 ]).to eq([ 1, "scheduled", "e1", 45 ])
      expect(adapter.events.last).to match([ :create, hash_including(attendee: "asha@x.in", summary: "Interview: Sales Intern (round 1)") ])
      expect(asha.reload.stage_label).to eq("Interview · round 1")

      patch "/hr/admin/hiring_candidates/#{asha.id}/interviews/#{first.id}", params: { date: 3.days.from_now.to_date, time: "15:00", minutes: 30 }
      expect(adapter.events.last.first).to eq(:update)
      patch "/hr/admin/hiring_candidates/#{asha.id}/interviews/#{first.id}", params: { date: "", time: "" }
      expect(flash[:alert]).to eq("Pick a date and time in the future.")

      schedule(minutes: 99)
      second = asha.interviews.order(:round).last
      expect([ second.round, (second.ends_at - second.starts_at) / 60 ]).to eq([ 2, 30 ])
      delete "/hr/admin/hiring_candidates/#{asha.id}/interviews/#{second.id}"
      expect([ second.reload.status, first.reload.status ]).to eq(%w[cancelled scheduled])
      get "/hr/admin/hiring_candidates/#{asha.id}"
      expect(response.body).to include("Round 2 cancelled", "Round 1 rescheduled for", "Round 1 scheduled for")
    end

    it "invites staff picked from the system and typed emails as guests on the same event" do
      asha.update!(stage: "interested")
      colleague = user_with_roles(HrLite::Role::EMPLOYEE, name: "Sadique", email: "sadique@earthlygroup.in")
      schedule_with = ->(**extra) { post "/hr/admin/hiring_candidates/#{asha.id}/interviews", params: { date: 2.days.from_now.to_date, time: "11:00", **extra } }

      schedule_with.(interviewer_emails: "ok@x.in, not-an-email")
      expect(flash[:alert]).to eq("Check these interviewer emails: not-an-email")
      schedule_with.(interviewer_emails: Array.new(11) { |i| "p#{i}@x.in" }.join(","))
      expect(flash[:alert]).to eq("Invite at most 10 interviewers.")

      schedule_with.(interviewer_ids: [ colleague.id ], interviewer_emails: "Guest@Example.com; sadique@earthlygroup.in asha@x.in")
      interview = asha.interviews.sole
      expect(interview.interviewers).to eq([ "sadique@earthlygroup.in", "guest@example.com" ])
      expect(adapter.events.last.last).to include(attendee: "asha@x.in", guests: [ "sadique@earthlygroup.in", "guest@example.com" ])
      expect(flash[:notice]).to eq("Invite sent for round 1 to the candidate and 2 interviewers.")
      get "/hr/admin/hiring_candidates/#{asha.id}"
      expect(response.body).to include("Other interviewers", "Sadique · sadique@earthlygroup.in",
                                       "With sadique@earthlygroup.in, guest@example.com", "with sadique@earthlygroup.in, guest@example.com")
    end

    it "keeps a record when Google refuses or does not answer" do
      asha.update!(stage: "interested")
      adapter.fail_with = HrLite::HiringDeliveryUnknown
      schedule
      expect(asha.interviews.sole.status).to eq("unknown")
      expect(flash[:alert]).to start_with("Google did not confirm")

      adapter.fail_with = HrLite::HiringDeliveryFailed
      schedule
      expect(asha.interviews.order(:id).last.status).to eq("failed")
      expect(flash[:alert]).to eq("Google refused: Calendar answered 503")

      adapter.fail_with = nil
      schedule
      scheduled = asha.interviews.find_by!(status: "scheduled")
      adapter.fail_with = HrLite::HiringDeliveryFailed
      patch "/hr/admin/hiring_candidates/#{asha.id}/interviews/#{scheduled.id}", params: { date: 3.days.from_now.to_date, time: "10:00" }
      expect(asha.timeline.first.action).to eq("hiring.interview_rescheduled_failed")

      delete "/hr/admin/hiring_candidates/#{asha.id}/interviews/#{scheduled.id}"
      expect([ scheduled.reload.status, asha.timeline.first.action ]).to eq([ "scheduled", "hiring.interview_cancelled_failed" ])
      schedule(date: "2026-13-45")
      expect(flash[:alert]).to eq("Pick a date and time in the future.")

      adapter.ready = false
      delete "/hr/admin/hiring_candidates/#{asha.id}/interviews/#{scheduled.id}"
      expect(flash[:alert]).to eq("Connect the hiring mailbox before scheduling.")
    end
  end

  describe "write with AI" do
    it "rewrites what HR typed into known fields, never saving it" do
      post "/hr/admin/hiring_templates", params: { ai: "1", hiring_template: { name: "", subject: "", body: "Hi Yuvraj, … Best, Khushboo" } }
      expect(response.body).to include("AI draft ready", "@position at escapes.asia", "Hi @first_name,", 'value="Interest check (AI)"')
      expect(adapter.drafted.first).to include("Hi Yuvraj")
      expect(adapter.drafted.last).to include("first_name", "round1_link")
      expect(HrLite::HiringTemplate.where(name: "Interest check (AI)")).to be_empty

      adapter.draft = { subject: "S", body: "Hi @nickname" }
      patch "/hr/admin/hiring_templates/#{template.id}", params: { ai: "1", hiring_template: { name: template.name, subject: "S", body: "B" } }
      expect(response.body).to include("AI could not draft this: it used unknown fields (@nickname)")
      expect(template.reload.subject).to include("@position")

      adapter.fail_with = HrLite::HiringDeliveryFailed
      post "/hr/admin/hiring_templates", params: { ai: "1", hiring_template: { name: "X", subject: "S", body: "B" } }
      expect(response.body).to include("AI could not draft this: model refused")
    end

    it "hides the button without an AI hook and limits drafts" do
      get "/hr/admin/hiring_templates/new"
      expect(response.body).to include("Write with AI")
      HrLite.config.hiring = Object.new
      get "/hr/admin/hiring_templates/new"
      expect(response.body).not_to include("Write with AI")
      HrLite.config.hiring = adapter
      20.times { post "/hr/admin/hiring_templates", params: { ai: "1", hiring_template: { name: "X", subject: "S", body: "B" } } }
      post "/hr/admin/hiring_templates", params: { ai: "1", hiring_template: { name: "X", subject: "S", body: "B" } }
      expect(flash[:alert]).to start_with("Twenty AI drafts an hour")
    end
  end

  describe "templates" do
    it "ships the approved outreach email and previews it for a real candidate" do
      expect(template.body).to include("Hi @first_name,", "Monthly Stipend: @stipend", "Best,\n@sender_name")
      get "/hr/admin/hiring_templates/#{template.id}/edit"
      expect(response.body).to include("Upload a candidate sheet to preview")

      asha = candidate("Asha")
      get "/hr/admin/hiring_templates/#{template.id}/edit", params: { candidate_id: asha.id }
      expect(response.body).to include("Hi Asha,", "This candidate would be left out: @programme (empty)", "Ready for 0 of 1 candidates",
                                       "<b>Khushboo</b>", "| escapes.asia")
      expect(response.body).not_to include("<script>x()")
    end

    it "creates and edits templates" do
      get "/hr/admin/hiring_templates"
      get "/hr/admin/hiring_templates/new"
      post "/hr/admin/hiring_templates", params: { hiring_template: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      post "/hr/admin/hiring_templates", params: { hiring_template: { name: "Next round", subject: "Round 2", body: "Hi @first_name" } }
      created = HrLite::HiringTemplate.find_by!(name: "Next round")
      patch "/hr/admin/hiring_templates/#{created.id}", params: { hiring_template: { body: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      patch "/hr/admin/hiring_templates/#{created.id}", params: { hiring_template: { body: "Hello" } }
      expect(created.reload.body).to eq("Hello")
    end
  end
end
