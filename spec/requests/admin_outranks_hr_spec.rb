require "rails_helper"

RSpec.describe "An admin decision stands over HR", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Hema") }
  let(:admin) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Om") }
  let(:office) { { lat: "28.6130", lng: "77.36606", accuracy_m: "20", geo_status: "ok" } }

  before do
    HrLite.config.office_geofence = true
    create(:office_location, lat: 28.61270779585808, lng: 77.36605830864376, radius_m: 500)
  end

  # The refusal message, or nil when the override went through.
  def override(by, mode)
    sign_in by
    post "/hr/admin/work_modes/#{employee.id}", params: { mode: mode, minutes: 30, title: "Call", reason: "Client call" }
    (flash[:notice] ? nil : flash[:alert]).tap { follow_redirect! } # following it clears the flash
  end

  it "lets HR override the system, refuses HR over an admin, and lets the admin override HR" do
    sign_in employee
    post "/hr/attendance/check_in", params: office

    expect(override(hr, "office")).to be_nil
    expect(override(admin, "office")).to be_nil
    expect(override(hr, "office")).to eq(HrLite::ADMIN_DECIDED)
    expect(HrLite::WorkStatus.for(employee.id).primary.event.set_by_id).to eq(admin.id)

    expect(override(hr, "busy")).to be_nil # another layer: not the admin's decision
    expect(override(admin, "meeting")).to be_nil
  end

  it "keeps admin-approved leave, admin-decided WFH and an admin's punch fix out of HR's hands" do
    leave = create(:leave_request, :approved, user: employee, decided_by_id: admin.id)
    expect(leave.cancellable_by?(hr)).to be(false)
    expect(leave.cancellable_by?(admin)).to be(true)
    expect(leave.tap { |l| l.decided_by_id = hr.id }.cancellable_by?(admin)).to be(true)

    wfh = HrLite::WfhRequest.new(user_id: employee.id, start_date: Date.current, end_date: Date.current,
                                 reason: "Plumber", status: "approved", decided_by_id: admin.id).tap { |r| r.save!(validate: false) }
    sign_in hr
    patch "/hr/admin/wfh_requests/#{wfh.id}", params: { status: "rejected", decision_note: "Not needed" }
    expect([ flash[:alert], wfh.reload.status ]).to eq([ HrLite::ADMIN_DECIDED, "approved" ])
    follow_redirect!

    date = Date.current - 2
    create(:attendance_record, user_id: employee.id, date: date, regularized_by_id: admin.id)
    fix = { date: date.to_s, attendance_record: { check_in_at: "#{date}T09:00", check_out_at: "#{date}T18:00",
                                                   status: "present", regularization_note: "Forgot" } }
    patch "/hr/admin/attendances/#{employee.id}", params: fix
    expect(flash[:alert]).to eq(HrLite::ADMIN_DECIDED)
    expect(HrLite::AttendanceRecord.find_by(user_id: employee.id, date: date).check_in_at).to be_nil

    sign_in admin
    patch "/hr/admin/attendances/#{employee.id}", params: fix
    expect(flash[:notice]).to eq("Attendance updated.")
  end
end
