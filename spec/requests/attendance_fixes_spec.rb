require "rails_helper"

RSpec.describe "Attendance corrections", type: :request do
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let(:employee) { create(:user, name: "Meera") }

  before { sign_in admin }

  describe "the admin fix form" do
    it "refuses a check-out with no check-in instead of writing an absent day" do
      date = Date.current - 2

      expect {
        patch "/hr/admin/attendances/#{employee.id}", params: {
          date: date.to_s,
          attendance_record: { check_in_at: "", check_out_at: "#{date}T18:00", status: "present",
                               regularization_note: "Forgot the morning punch" }
        }
      }.not_to change(HrLite::AttendanceRecord, :count)

      expect(flash[:alert]).to include("check-in time is required")
    end

    it "says nothing was removed rather than emailing a removal that never happened" do
      date = Date.current - 3

      expect {
        patch "/hr/admin/attendances/#{employee.id}", params: {
          date: date.to_s,
          attendance_record: { check_in_at: "", check_out_at: "", regularization_note: "checking" }
        }
      }.not_to change(HrLite::AuditLog, :count)

      expect(flash[:notice]).to include("Nothing to remove")
    end
  end

  describe "a shift that runs past midnight" do
    it "offers yesterday's check-out instead of a fresh check-in" do
      create(:attendance_record, user: employee, date: Date.current - 1,
             check_in_at: (Date.current - 1).in_time_zone.change(hour: 21), check_out_at: nil)

      sign_in employee
      get "/hr/attendance"

      expect(response.body).to include("Check out yesterday's shift")
      expect(response.body).not_to include(">Check in<")
    end
  end

  describe "the geolocation status an employee submits" do
    it "is confined to what a browser can actually report" do
      sign_in employee
      post "/hr/attendance/check_in", params: { geo_status: "verified at HQ, GPS confirmed" }

      record = HrLite::AttendanceRecord.find_by(user_id: employee.id, date: Date.current)
      expect(record.flag_note).to eq("Check-in without GPS (unavailable)")
    end

    it "reads as unavailable when JavaScript never filled the field" do
      sign_in employee
      post "/hr/attendance/check_in", params: { geo_status: "" }

      record = HrLite::AttendanceRecord.find_by(user_id: employee.id, date: Date.current)
      expect(record.flag_note).to eq("Check-in without GPS (unavailable)")
    end
  end
end
