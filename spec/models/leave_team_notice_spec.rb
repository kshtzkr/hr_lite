require "rails_helper"

RSpec.describe "Leave team notice" do
  let(:requester) { create(:user, name: "Meera", email: "meera@x.test") }
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let!(:colleague) { create(:user, name: "Dev", email: "dev@x.test") }
  let(:type) { create(:leave_type, name: "Casual", annual_quota: 12) }
  let(:monday) { Date.new(2027, 7, 5) }

  before { travel_to(Date.new(2027, 7, 1)) }
  after { travel_back }

  def approved_request
    request = create(:leave_request, user: requester, leave_type: type,
                     start_date: monday, end_date: monday, reason: "medical thing")
    request.approve!(actor: admin)
    request
  end

  it "bells and emails the whole team except the requester, without the reason" do
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }
    emails = []
    allow(HrLite::EventMailer).to receive(:event) do |**kw|
      emails << kw
      instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    end

    approved_request

    notices = bells.select { |b| b[:kind] == "leave.team_notice" }
    expect(notices.map { |b| b[:user] }).to include(colleague, admin)
    expect(notices.map { |b| b[:user] }).not_to include(requester)
    expect(notices.first[:title]).to include("Meera is on leave").and include("Casual")
    expect(notices.first[:title]).not_to include("medical")

    team_emails = emails.select { |e| e[:subject].to_s.include?("is on leave") }
    expect(team_emails.map { |e| e[:to] }).to include("dev@x.test")
    expect(team_emails.map { |e| e[:to] }).not_to include("meera@x.test")
  end

  it "never notifies exited staff" do
    gone = create(:user, name: "Gone", email: "gone@x.test")
    create(:employee_profile, user: gone, date_of_exit: Date.new(2027, 1, 31))
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    approved_request
    notices = bells.select { |b| b[:kind] == "leave.team_notice" }
    expect(notices.map { |b| b[:user] }).to include(colleague)
    expect(notices.map { |b| b[:user] }).not_to include(gone)
  end

  it "keeps default rows for events a stale host matrix override doesn't know" do
    # A host that pinned an override on an older gem version: no
    # leave.team_notice row at all — the default must still fire.
    HrLite.config.notification_matrix = { "leave.requested" => { bell: false, email: false, leadership_email: false, leadership_bell: false } }
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    approved_request
    expect(bells.map { |b| b[:kind] }).to include("leave.team_notice")
    expect(bells.map { |b| b[:kind] }).not_to include("leave.requested")
  end

  it "stays quiet when the host mutes the matrix row" do
    HrLite.config.notification_matrix = HrLite::Notifications::DEFAULT_MATRIX.merge(
      "leave.team_notice" => { bell: false, email: false, leadership_email: false, leadership_bell: false }
    )
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    approved_request
    expect(bells.map { |b| b[:kind] }).not_to include("leave.team_notice")
  end

  it "skips the broadcast entirely when there is nobody else" do
    colleague.destroy!
    requester.update!(admin: true)
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    request = create(:leave_request, user: requester, leave_type: type,
                     start_date: monday, end_date: monday)
    request.approve!(actor: requester)
    expect(bells.map { |b| b[:kind] }).not_to include("leave.team_notice")
  end
end
