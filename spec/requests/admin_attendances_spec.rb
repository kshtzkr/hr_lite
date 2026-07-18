require "rails_helper"

RSpec.describe "Admin attendances", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:employee) { create(:user, name: "Asha") }

  describe "authorization" do
    it "blocks employees from the team view" do
      sign_in employee
      get "/hr/admin/attendances"
      expect(response).to redirect_to("/hr/")
    end

    it "admits admins and leadership" do
      sign_in admin
      get "/hr/admin/attendances"
      expect(response).to have_http_status(:ok)

      HrLite.config.leadership_emails = [ "lead@x.test" ]
      sign_in create(:user, email: "lead@x.test")
      get "/hr/admin/attendances"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /hr/admin/attendances (day view)" do
    before { sign_in admin }

    it "lists every employee with punch state and flags" do
      create(:attendance_record, :checked_in, :flagged, user: employee, date: Date.current)
      get "/hr/admin/attendances"

      expect(response.body).to include("Asha").and include("Flagged").and include("No punch")
    end

    it "walks to other dates and falls back on garbage" do
      get "/hr/admin/attendances", params: { date: (Date.current - 3).to_s }
      expect(response.body).to include((Date.current - 3).strftime("%d %B %Y"))

      get "/hr/admin/attendances", params: { date: "garbage" }
      expect(response.body).to include(Date.current.strftime("%d %B %Y"))
    end
  end

  describe "GET /hr/admin/attendances/:user_id (month + fix form)" do
    before { sign_in admin }

    it "shows the month grid and a fix form for ?date" do
      create(:attendance_record, :checked_out, user: employee, date: Date.current - 1)
      get "/hr/admin/attendances/#{employee.id}", params: { date: (Date.current - 1).to_s }

      expect(response.body).to include("Fix #{(Date.current - 1).strftime('%A, %d %B')}")
        .and include("regularization_note")
    end
  end

  describe "PATCH /hr/admin/attendances/:user_id (regularization)" do
    before { sign_in admin }

    let(:date) { Date.current - 1 }

    it "requires a note" do
      patch "/hr/admin/attendances/#{employee.id}", params: {
        date: date.to_s, attendance_record: { check_in_at: "#{date}T09:30", regularization_note: " " }
      }
      expect(flash[:alert]).to include("note is required")
      expect(HrLite::AttendanceRecord.count).to eq(0)
    end

    it "creates the fixed record, audits it and notifies the employee" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }

      expect {
        patch "/hr/admin/attendances/#{employee.id}", params: {
          date: date.to_s,
          attendance_record: { check_in_at: "#{date}T09:30", check_out_at: "#{date}T18:00",
                               status: "present", regularization_note: "Forgot phone at home" }
        }
      }.to change(HrLite::AttendanceRecord, :count).by(1)
        .and change(HrLite::AuditLog, :count).by(1)

      record = HrLite::AttendanceRecord.last
      expect(record.regularized_by_id).to eq(admin.id)
      expect(record.regularization_note).to eq("Forgot phone at home")
      expect(bells.map { |b| b[:kind] }).to include("attendance.regularized")
      expect(bells.find { |b| b[:kind] == "attendance.regularized" }[:user]).to eq(employee)
    end

    it "removes the punch when both times are cleared" do
      create(:attendance_record, :checked_in, user: employee, date: date)

      expect {
        patch "/hr/admin/attendances/#{employee.id}", params: {
          date: date.to_s,
          attendance_record: { check_in_at: "", check_out_at: "", regularization_note: "Punched by mistake" }
        }
      }.to change(HrLite::AttendanceRecord, :count).by(-1)
      expect(flash[:notice]).to eq("Punch removed.")
    end

    it "surfaces validation errors" do
      patch "/hr/admin/attendances/#{employee.id}", params: {
        date: date.to_s,
        attendance_record: { check_in_at: "#{date}T18:00", check_out_at: "#{date}T09:00",
                             regularization_note: "oops" }
      }
      expect(flash[:alert]).to include("must be after check-in")
    end
  end
end
