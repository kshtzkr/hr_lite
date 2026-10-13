require "rails_helper"

RSpec.describe "Work mode timeline and status", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:office) { { lat: "28.6130", lng: "77.36606", accuracy_m: "20", geo_status: "ok" } }
  let(:tuesday) { Date.new(2026, 10, 20) }

  before do
    HrLite.config.office_geofence = true
    create(:office_location, lat: 28.61270779585808, lng: 77.36605830864376, radius_m: 500)
    travel_to(Time.zone.local(2026, 10, 20, 9, 30))
    sign_in employee
  end

  after { travel_back }

  def status(at: Time.current) = HrLite::WorkStatus.for(employee.id, at: at)
  def timeline = HrLite::WorkModeEvent.where(user_id: employee.id).order(:started_at, :id).pluck(:mode, :source, :end_reason)

  it "opens a system mode at check-in and Offline at check-out, keeping the history" do
    post "/hr/attendance/check_in", params: office
    expect(status.primary).to have_attributes(mode: "office", source: "system")

    travel_to(Time.zone.local(2026, 10, 20, 18, 0))
    post "/hr/attendance/check_out", params: office
    expect(status.primary).to have_attributes(mode: "offline", source: "system")
    expect(timeline).to eq([ [ "office", "system", "checked_out" ], [ "offline", "system", nil ] ])
    expect(HrLite::AttendanceRecord.last.work_mode).to eq("office")
  end

  it "puts holidays and full-day leave above any work mode, and names sick leave" do
    HrLite::WorkModeEvent.start!(user_id: employee.id, mode: "wfh", source: "employee") # a stale status left open
    sick = create(:leave_type, code: "SL", name: "Sick leave")
    create(:leave_request, :approved, user: employee, leave_type: sick, start_date: tuesday, end_date: tuesday)
    expect(status.primary).to have_attributes(mode: "sick_leave", label: "Sick leave")

    HrLite::LeaveRequest.update_all(leave_type_id: create(:leave_type, code: "CL").id)
    expect(status.primary.mode).to eq("on_leave")

    HrLite::LeaveRequest.delete_all
    create(:holiday, date: tuesday)
    expect(status.primary.mode).to eq("holiday")
    expect(status.overlay).to be_nil
  end

  it "keeps the work mode on a half-day leave and marks the half day" do
    post "/hr/attendance/check_in", params: office
    create(:leave_request, :approved, user: employee, start_date: tuesday, end_date: tuesday, half_day_part: "second")
    expect(status.primary.mode).to eq("office")
    expect(status.half_day_leave).to be_present
  end

  it "drops an overlay once its time has passed, even before the job runs" do
    post "/hr/attendance/check_in", params: office
    HrLite::WorkModeEvent.start!(user_id: employee.id, mode: "busy", source: "employee", ends_at: 30.minutes.from_now)
    expect(status.overlay.mode).to eq("busy")
    expect(status(at: 31.minutes.from_now).overlay).to be_nil
    expect(status(at: 31.minutes.from_now).primary.mode).to eq("office")
  end

  it "is Offline with no check-in on a working day, Weekend on a weekend" do
    expect(status.primary.mode).to eq("offline")
    expect(status(at: Time.zone.local(2026, 10, 24, 11)).primary.mode).to eq("weekend")
  end

  it "closes a forgotten mode at the nightly day close" do
    post "/hr/attendance/check_in", params: office
    travel_to(Time.zone.local(2026, 10, 20, 23, 55))
    HrLite::AttendanceCloseJob.perform_now(date: tuesday)
    expect(timeline.first).to eq([ "office", "system", "day_closed" ])
    expect(HrLite::WorkModeEvent.open.where.not(mode: "offline")).to be_empty
  end

  it "allows only one open row per layer" do
    HrLite::WorkModeEvent.start!(user_id: employee.id, mode: "office", source: "system")
    HrLite::WorkModeEvent.start!(user_id: employee.id, mode: "travelling", source: "employee")
    expect(HrLite::WorkModeEvent.open.where(user_id: employee.id).pluck(:mode)).to eq([ "travelling" ])
    expect do
      HrLite::WorkModeEvent.create!(user_id: employee.id, mode: "wfh", source: "system", started_at: Time.current)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
