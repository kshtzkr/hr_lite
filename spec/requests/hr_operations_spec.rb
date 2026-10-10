require "rails_helper"

RSpec.describe "HR operations: ID card print requests and recorded leave", type: :request do
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Ananya", email: "ananya@x.test") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra", email: "chitra@x.test") }
  let!(:profile) { create(:employee_profile, user: employee, employee_code: "ESA-000427") }
  let(:emails) { [] }

  before do
    allow(HrLite::EventMailer).to receive(:event) do |**kw|
      emails << kw
      instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    end
  end

  def ask_for_card = post("/hr/hr_requests", params: { hr_request: { category: "id_card", subject: "Please print my ID card" } })

  def with_photo
    profile.photo.attach(io: StringIO.new("\x89PNG\r\n\x1A\n".b), filename: "me.png", content_type: "image/png")
  end

  describe "asking for a printed ID card" do
    before { hr && sign_in(employee) }

    it "is refused until the card has a photo" do
      expect { ask_for_card }.not_to change(HrLite::HrRequest, :count)
      expect(response).to redirect_to("/hr/id_card")
      expect(flash[:alert]).to include("Add your photo")
    end

    it "emails and bells every HR desk holder, and the card shows it is requested" do
      with_photo
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }

      ask_for_card

      expect(emails.map { |e| e[:to] }).to include("chitra@x.test")
      expect(bells.map { |b| b[:user] }).to include(hr)
      get "/hr/id_card"
      expect(response.body).to include("Printed card requested on")
    end

    it "refuses a second request while one is open" do
      with_photo
      ask_for_card
      expect { ask_for_card }.not_to change(HrLite::HrRequest, :count)
      expect(flash[:alert]).to include("already requested")
    end

    it "shows the issued month once HR marks it done, and allows a reprint" do
      with_photo
      ask_for_card
      travel_to(Time.zone.local(2026, 10, 3)) do
        HrLite::HrRequest.last.resolve!(actor: hr, resolution: "Printed, collect from reception")
      end

      get "/hr/id_card"
      expect(response.body).to include("Oct 2026").and include("Request printed card")
      expect { ask_for_card }.to change(HrLite::HrRequest, :count).by(1)
    end

    it "gives the desk a link to print the card" do
      with_photo
      ask_for_card
      sign_in hr
      get "/hr/admin/hr_requests/#{HrLite::HrRequest.last.id}"
      expect(response.body).to include("/hr/id_card/#{employee.id}")
    end
  end

  describe "recording leave somebody forgot to apply for" do
    let(:type) { create(:leave_type, name: "Casual", annual_quota: 12) }
    let(:monday) { Date.new(2027, 7, 5) }

    around { |example| travel_to(Date.new(2027, 7, 12)) { example.run } }

    def record(code: "ESA-000427", from: monday, to: monday, leave_type: type)
      post "/hr/admin/leave_requests", params: {
        employee_code: code, leave_request: { leave_type_id: leave_type.id, start_date: from, end_date: to }
      }
    end

    it "saves it approved, debits the balance and emails the employee, not the approvers" do
      sign_in hr
      record

      leave = HrLite::LeaveRequest.last
      expect(leave).to have_attributes(status: "approved", user_id: employee.id, created_by_id: hr.id, decided_by_id: hr.id)
      expect(leave.balance.used).to eq(1)
      expect(emails.map { |e| e[:subject] }).to include(a_string_including("Leave approved"))
      expect(emails.map { |e| e[:subject] }).not_to include(a_string_including("applied for"))
      expect(emails.map { |e| e[:subject] }).not_to include(a_string_including("is on leave"))
    end

    it "refuses somebody outside the recorder's reach and saves nothing" do
      manager = user_with_roles(HrLite::Role::MANAGER, name: "Rohan")
      sign_in manager
      expect { record }.not_to change(HrLite::LeaveRequest, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Pick an employee from the list")
    end

    it "records leave the balance does not cover as loss of pay" do
      sign_in hr
      tight = create(:leave_type, name: "Tight", annual_quota: 0)
      record(leave_type: tight)
      expect(HrLite::LeaveRequest.last).to have_attributes(status: "approved", paid_days: 0)
    end

    it "refuses comp-off with no credit and saves nothing" do
      sign_in hr
      comp_off = create(:leave_type, :comp_off, name: "Comp off")
      expect { record(leave_type: comp_off) }.not_to change(HrLite::LeaveRequest, :count)
      expect(response.body).to include("Not enough Comp off balance")
    end

    it "fixes recorded past leave in place with a reason, no cancel" do
      sign_in hr
      record
      leave = HrLite::LeaveRequest.last
      fix = ->(reason) { patch "/hr/admin/leave_requests/#{leave.id}", params: { correction_reason: reason, leave_request: { leave_type_id: type.id, start_date: monday, end_date: monday + 1 } } }

      get "/hr/admin/leave_requests/#{leave.id}/edit"
      expect(response.body).to include("Reason for the fix")

      fix.call("")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(leave.reload.end_date).to eq(monday)

      fix.call("Was out Tuesday too")
      expect(leave.reload).to have_attributes(status: "approved", end_date: monday + 1, decision_note: "Corrected: Was out Tuesday too")
      expect(leave.balance.used).to eq(2)
      expect(HrLite::AuditLog.where(action: "leave.corrected")).to exist
    end

    it "lists the people HR can record leave for" do
      sign_in hr
      get "/hr/admin/leave_requests/new"
      expect(response.body).to include('value="ESA-000427"').and include("Ananya")
    end
  end

  it "emails every approver when an employee applies" do
    user_with_roles(HrLite::Role::HR, name: "Chitra", email: "chitra@x.test")
    type = create(:leave_type, name: "Casual", annual_quota: 12)
    travel_to(Date.new(2027, 7, 1)) do
      create(:leave_request, user: employee, leave_type: type, start_date: Date.new(2027, 7, 5), end_date: Date.new(2027, 7, 5))
    end
    expect(emails).to include(a_hash_including(to: "chitra@x.test", subject: a_string_including("applied for")))
  end

  it "gives a new hire the Employee role so they can use self-service" do
    HrLite::RoleSeeds.call
    fresh = create(:employee_profile)
    expect(HrLite::Access.for(fresh.user).can?("hr_request.raise")).to be(true)
  end
end
