require "rails_helper"

RSpec.describe "Policies, announcements and holiday notices", type: :request do
  let(:lead) { user_with_roles(HrLite::Role::LEADERSHIP, name: "Asha", email: "asha@x.test") }
  let!(:staff) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera", email: "meera@x.test") }
  let(:emails) { [] }
  let(:bells) { [] }

  before do
    HrLite.config.notify = ->(**kw) { bells << kw }
    allow(HrLite::EventMailer).to receive(:event) do |**kw|
      emails << kw
      instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    end
  end

  def publish(title: "Leave policy", ack: "1")
    post "/hr/admin/policies", params: { policy: { title: title, body: "Apply two days ahead.",
                                                   effective_from: "2026-10-01", acknowledgement_required: ack } }
  end

  describe "publishing" do
    before { sign_in lead }

    it "tells every current employee by email and bell, and skips people who have left" do
      gone = create(:user, name: "Gone", email: "gone@x.test")
      create(:employee_profile, user: gone, date_of_joining: Date.new(2020, 1, 1), date_of_exit: Date.new(2021, 1, 1))

      publish

      expect(HrLite::Policy.last).to have_attributes(published: true, version: 1)
      expect(emails.map { |e| e[:to] }).to include("meera@x.test")
      expect(emails.map { |e| e[:to] }).not_to include("gone@x.test")
      expect(emails.map { |e| e[:subject] }).to include("Policy: Leave policy (please read and acknowledge)")
      expect(bells.select { |b| b[:kind] == "policy.published" }.map { |b| b[:user] }).to include(staff)
    end

    it "opens the publish form as a policy by default" do
      get "/hr/admin/policies/new"
      expect(response.body).to include("Publish a policy or announcement").and include('checked="checked"')
    end

    it "calls it an announcement when nobody has to acknowledge it" do
      publish(title: "Office closed Friday", ack: "0")
      expect(emails.map { |e| e[:subject] }).to include("Announcement: Office closed Friday")
    end

    it "publishes the same title again as the next version" do
      publish
      publish
      expect(HrLite::Policy.where(title: "Leave policy").pluck(:version)).to contain_exactly(1, 2)
      get "/hr/admin/policies"
      expect(response.body).to include("v2")
    end

    it "keeps a policy with no text off the wire" do
      expect { post "/hr/admin/policies", params: { policy: { title: "Empty", body: "" } } }
        .not_to change(HrLite::Policy, :count)
      expect(emails).to be_empty
    end
  end

  it "refuses somebody without policy.manage" do
    sign_in staff
    publish
    expect(HrLite::Policy.count).to eq(0)
    expect(response).to redirect_to("/hr/")
  end

  describe "holidays" do
    before { sign_in lead }

    it "tells everyone about a new holiday" do
      post "/hr/admin/holidays", params: { holiday: { date: "2026-11-12", name: "Diwali" } }
      expect(emails).to include(a_hash_including(to: "meera@x.test", subject: "Holiday added: Diwali on Thu 12 Nov 2026"))
    end

    it "sends one notice for a whole pasted list, not one per line" do
      post "/hr/admin/holidays/bulk_create", params: { lines: "2026-12-25, Christmas\n2027-01-26, Republic Day\n" }
      expect(emails.count { |e| e[:to] == "meera@x.test" }).to eq(1)
      expect(emails.map { |e| e[:subject] }).to include("2 holidays added to the calendar")
    end
  end

  describe "the notifications link" do
    before { sign_in staff }

    it "is absent until the host configures one" do
      get "/hr/"
      expect(response.body).not_to include("hrl-bell")
    end

    it "shows the unread count the host reports" do
      HrLite.config.notifications = ->(_user) { { url: "https://cms.test/notifications", unread: 3 } }
      get "/hr/"
      expect(response.body).to include('href="https://cms.test/notifications"').and include('hrl-bell__count">3<')
    end
  end
end
