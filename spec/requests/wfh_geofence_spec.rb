require "rails_helper"

RSpec.describe "Office geofence and WFH", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:colleague) { create(:user, name: "Dev") }
  let(:admin) { create(:user, :admin) }
  let(:inside) { { lat: "28.6145", lng: "77.36604", accuracy_m: "30", geo_status: "ok" } } # ~200 m
  let(:outside) { { lat: "28.6187", lng: "77.36604", accuracy_m: "30", geo_status: "ok" } } # ~670 m

  before do
    HrLite.config.office_geofence = true
    create(:office_location, name: "Head office", lat: 28.612703160286397, lng: 77.36603718690168, radius_m: 500)
    sign_in employee
  end

  def wfh(status, user: employee, from: Date.current, to: Date.current)
    HrLite::WfhRequest.new(user_id: user.id, start_date: from, end_date: to, reason: "Plumber visit", status: status)
                      .tap { |r| r.save!(validate: false) }
  end

  def record = HrLite::AttendanceRecord.find_by(user_id: employee.id, date: Date.current)

  # An approved, active home location where `outside` is.
  def home_at_outside
    HrLite::WorkLocation.create!(user_id: employee.id, name: "Home", lat: 28.6187, lng: 77.36604, accuracy_m: 20,
                                 status: "approved", active: true)
  end

  describe "check-in" do
    it "offers Request WFH on the home page" do
      get "/hr"
      expect(response.body).to include(%(href="/hr/wfh_requests">Request WFH</a>))
    end

    it "allows a check-in inside the 500 m radius" do
      post "/hr/attendance/check_in", params: inside
      expect(record.check_in_at).to be_present
      expect(record.wfh_request_id).to be_nil
    end

    it "refuses a check-in outside the radius without approved WFH" do
      post "/hr/attendance/check_in", params: outside
      expect(flash[:alert]).to eq(HrLite::AttendancePuncher::OFF_SITE_MESSAGE)
      expect(record).to be_nil
      follow_redirect!
      expect(response.body).to include(%(href="/hr/wfh_requests">Request WFH</a>))
    end

    it "refuses a fix too vague to prove presence (accuracy wider than the radius)" do
      post "/hr/attendance/check_in", params: inside.merge(accuracy_m: "1500")
      expect(record).to be_nil
    end

    it "explains a denied or failed location and does not record a punch" do
      post "/hr/attendance/check_in", params: { geo_status: "denied" }
      expect(flash[:alert]).to include("could not read your location (denied)").and include("WFH")
      post "/hr/attendance/check_in", params: { geo_status: "timeout" }
      expect(flash[:alert]).to include("(timeout)")
      expect(record).to be_nil
    end

    it "lets an approved WFH day check in remotely and links the record" do
      request = wfh("approved")
      home_at_outside
      post "/hr/attendance/check_in", params: outside
      expect(record.wfh_request_id).to eq(request.id)
      expect(record).not_to be_flagged
      get "/hr/attendance"
      expect(response.body).to include("WFH")
    end

    it "counts a check-in inside the radius as office even with WFH approved" do
      wfh("approved")
      post "/hr/attendance/check_in", params: inside
      expect(record).to have_attributes(work_mode: "office", wfh_request_id: nil)
    end

    it "treats permanent WFH as standing approval at the home location, and inside the radius as office" do
      create(:employee_profile, user: employee, permanent_wfh: true)
      home_at_outside
      post "/hr/attendance/check_in", params: outside
      expect(record).to have_attributes(work_mode: "wfh", wfh_request_id: nil)

      record.destroy
      post "/hr/attendance/check_in", params: inside
      expect(record.work_mode).to eq("office")
    end

    it "gives no exception for rejected or other-date requests" do
      wfh("rejected")
      wfh("approved", from: Date.current + 1, to: Date.current + 2)
      post "/hr/attendance/check_in", params: outside
      expect(flash[:alert]).to eq(HrLite::AttendancePuncher::OFF_SITE_MESSAGE)
      expect(record).to be_nil
    end

    it "lets a pending request for today check in, flags the day and tells HR the reason" do
      home_at_outside
      request = wfh("pending")
      sent = []
      allow(HrLite::Notifications).to receive(:publish) { |event, **opts| sent << [ event, opts[:body] ] }
      post "/hr/attendance/check_in", params: outside
      expect(record).to have_attributes(work_mode: "wfh", wfh_request_id: request.id, flagged: true)
      expect(sent).to include([ "attendance.flagged", "WFH request pending HR approval: Plumber visit" ])
    end

    it "keeps check-out working off-site after an office check-in" do
      post "/hr/attendance/check_in", params: inside
      post "/hr/attendance/check_out", params: outside
      expect(record.check_out_at).to be_present
      expect(record.flag_note).to include("Check-out")
    end
  end

  describe "employee requests" do
    it "creates a request and tells HR" do
      admin
      expect(HrLite).to receive(:notify).with(hash_including(kind: "wfh.requested")).at_least(:once)
      post "/hr/wfh_requests", params: { wfh_request: { start_date: Date.current, end_date: Date.current + 2, reason: "Recovering" } }
      expect(HrLite::WfhRequest.last).to have_attributes(user_id: employee.id, status: "pending")
      expect(HrLite::AuditLog.where(action: "wfh.requested").count).to eq(1)
    end

    it "still saves when the notification fails" do
      allow(HrLite::Notifications).to receive(:publish).and_raise("smtp down")
      post "/hr/wfh_requests", params: { wfh_request: { start_date: Date.current, end_date: Date.current, reason: "Recovering" } }
      expect(HrLite::WfhRequest.count).to eq(1)
    end

    it "refuses past dates, dates past 30 days, reversed ranges and a missing reason" do
      [ [ Date.current - 1, Date.current, "x" ], [ Date.current, Date.current + 31, "x" ],
        [ Date.current + 3, Date.current + 1, "x" ], [ Date.current, Date.current, "" ] ].each do |from, to, reason|
        post "/hr/wfh_requests", params: { wfh_request: { start_date: from, end_date: to, reason: reason } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(HrLite::WfhRequest.count).to eq(0)
    end

    it "refuses overlaps with a live request but allows them after a rejection" do
      wfh("approved", from: Date.current + 2, to: Date.current + 4)
      post "/hr/wfh_requests", params: { wfh_request: { start_date: Date.current + 4, end_date: Date.current + 5, reason: "x" } }
      expect(response.body).to include("already have a pending or approved")

      HrLite::WfhRequest.last.update_columns(status: "rejected")
      post "/hr/wfh_requests", params: { wfh_request: { start_date: Date.current + 4, end_date: Date.current + 5, reason: "x" } }
      expect(HrLite::WfhRequest.pending.count).to eq(1)
    end

    it "shows only my own requests and ignores a posted status or user" do
      wfh("pending", user: colleague).update_columns(reason: "Colleague secret")
      post "/hr/wfh_requests", params: { wfh_request: { start_date: Date.current, end_date: Date.current, reason: "Mine",
                                                         status: "approved", user_id: colleague.id } }
      expect(HrLite::WfhRequest.find_by(reason: "Mine")).to have_attributes(user_id: employee.id, status: "pending")
      get "/hr/wfh_requests"
      expect(response.body).to include("Mine").and include('min="').and include('max="')
      expect(response.body).not_to include("Colleague secret")
    end

    it "cannot reach the HR decisions" do
      request = wfh("pending")
      post "/hr/admin/wfh_requests/#{request.id}/approve"
      expect(request.reload).to be_pending
    end
  end

  describe "HR decisions" do
    before { sign_in admin }

    it "approves and rejects (with a required remark) and tells the employee" do
      approve_me = wfh("pending", from: Date.current + 1, to: Date.current + 1)
      reject_me = wfh("pending", from: Date.current + 3, to: Date.current + 3)

      post "/hr/admin/wfh_requests/#{approve_me.id}/approve"
      expect(approve_me.reload).to have_attributes(status: "approved", decided_by_id: admin.id)

      post "/hr/admin/wfh_requests/#{reject_me.id}/reject"
      expect(reject_me.reload).to be_pending
      post "/hr/admin/wfh_requests/#{reject_me.id}/reject", params: { decision_note: "Client visit that day" }
      expect(reject_me.reload).to have_attributes(status: "rejected", decision_note: "Client visit that day")
      expect(HrLite::AuditLog.where(action: %w[wfh.approved wfh.rejected]).count).to eq(2)

      sign_in employee
      get "/hr/wfh_requests"
      expect(response.body).to include("Client visit that day")
    end

    it "gives WFH directly for up to 60 days, approved at once" do
      create(:employee_profile, user: employee)
      post "/hr/admin/wfh_requests", params: { user_id: employee.id, start_date: Date.current + 1, end_date: Date.current + 60, reason: "Post-surgery" }
      expect(HrLite::WfhRequest.last).to have_attributes(status: "approved", created_by_id: admin.id, decided_by_id: admin.id)
      expect(HrLite::AuditLog.where(action: "wfh.granted").count).to eq(1)

      post "/hr/admin/wfh_requests", params: { user_id: colleague.id, start_date: Date.current, end_date: Date.current + 60, reason: "x" }
      expect(flash[:alert]).to include("at most 60 days")
      post "/hr/admin/wfh_requests", params: { user_id: colleague.id, start_date: Date.current - 1, end_date: Date.current, reason: "x" }
      expect(flash[:alert]).to include("past")
      post "/hr/admin/wfh_requests", params: { user_id: admin.id, start_date: Date.current, end_date: Date.current, reason: "x" }
      expect(response).to have_http_status(:not_found)
      expect(HrLite::WfhRequest.count).to eq(1)
    end

    it "does not let an employee give WFH" do
      sign_in employee
      post "/hr/admin/wfh_requests", params: { user_id: employee.id, start_date: Date.current, end_date: Date.current, reason: "x" }
      expect(HrLite::WfhRequest.count).to eq(0)
    end

    it "cannot re-decide a decided request or decide their own" do
      decided = wfh("approved")
      post "/hr/admin/wfh_requests/#{decided.id}/reject", params: { decision_note: "Changed my mind" }
      expect(decided.reload).to be_approved

      own = wfh("pending", user: admin)
      post "/hr/admin/wfh_requests/#{own.id}/approve"
      expect(response).to have_http_status(:not_found)
      expect(own.reload).to be_pending
    end

    it "counts each employee once and filters the board" do
      create(:employee_profile, user: employee, department: "Sales")
      create(:employee_profile, user: colleague, department: "Ops")
      wfh("approved", from: Date.current, to: Date.current + 1)
      wfh("pending", from: Date.current + 5, to: Date.current + 5)
      wfh("approved", user: colleague, from: Date.current, to: Date.current)
      wfh("rejected", user: colleague, from: Date.current + 2, to: Date.current + 2)
      create(:attendance_record, user: colleague, date: Date.current, check_in_at: Time.current)

      get "/hr/admin/wfh_requests"
      kpis = response.body.scan(%r{hrl-kpi__value">(\d+)<}).flatten.map(&:to_i)
      expect(kpis).to eq([ 2, 2, 1, 1, 2 ]) # requested, approved, pending, rejected, home today

      get "/hr/admin/wfh_requests", params: { department: "Sales" }
      expect(response.body.scan(%r{hrl-kpi__value">(\d+)<}).flatten.map(&:to_i)).to eq([ 1, 1, 1, 0, 1 ])

      get "/hr/admin/wfh_requests", params: { q: "dev", status: "rejected" }
      expect(response.body).to include("Dev").and include("Rejected")

      create(:employee_profile, user: create(:user, name: "Ravi"), permanent_wfh: true)
      HrLite::EmployeeProfile.find_by(user_id: employee.id).update!(permanent_wfh: true) # also has a request: counted once
      get "/hr/admin/wfh_requests"
      expect(response.body.scan(%r{hrl-kpi__value">(\d+)<}).flatten.last.to_i).to eq(3)
      expect(response.body).to include("Permanent WFH")

      get "/hr/admin/wfh_requests", params: { attendance: "not_checked_in" }
      home = response.body[/Working from home on.*?<\/section>/m]
      expect(home).to include("Asha").and include("Ravi")
      expect(home).not_to include("Dev")
    end
  end
end
