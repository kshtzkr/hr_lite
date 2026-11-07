require "rails_helper"

RSpec.describe "Taking a checked-in day out of leave", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Hema") }
  let(:admin) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Om") }
  let(:type) { create(:leave_type) }
  let(:mon) { Date.new(2026, 11, 16) }

  before do
    travel_to(Time.zone.local(2026, 11, 18, 12))
    sign_in hr
  end

  def leave(from, to, **attrs)
    create(:leave_request, :approved, user: employee, leave_type: type, start_date: from, end_date: to, decided_by_id: hr.id, **attrs)
  end

  def take_out(request, date, note: "Came in for the audit")
    post "/hr/admin/leave_requests/#{request.id}/cancel_day", params: { date: date.to_s, decision_note: note }
  end

  def used = HrLite::LeaveBalance.for(employee, type, 2026).used

  it "offers it on the Fix panel and splits the leave around a middle day, paid days first" do
    request = leave(mon, mon + 2, paid_days: 2)
    create(:attendance_record, user_id: employee.id, date: mon + 1, check_in_at: (mon + 1).in_time_zone.change(hour: 10))
    get "/hr/admin/attendances/#{employee.id}", params: { date: (mon + 1).to_s }
    expect(response.body).to include("Checked in on leave", "Take 17 Nov out of leave")

    take_out(request, mon + 1)
    expect(flash[:notice]).to eq("17 Nov taken out of leave. The day is back in the balance.")
    parts = HrLite::LeaveRequest.where(user_id: employee.id).order(:start_date)
    expect(parts.map { |r| [ r.start_date, r.end_date, r.days_count, r.paid_days, r.status ] })
      .to eq([ [ mon, mon, 1, 1, "approved" ], [ mon + 2, mon + 2, 1, 1, "approved" ] ])
    expect(used).to eq(2)
    expect(HrLite::AuditLog.where(action: "leave.day_cancelled").count).to eq(1)
  end

  it "trims an edge day and cancels a one-day leave" do
    trimmed = leave(mon, mon + 1)
    take_out(trimmed, mon)
    expect(trimmed.reload).to have_attributes(start_date: mon + 1, end_date: mon + 1, days_count: 1)

    take_out(trimmed, mon + 1)
    expect(trimmed.reload.status).to eq("cancelled")
    expect(used).to eq(0)
  end

  it "needs a reason, a day inside the leave, and leaves an admin's approval to an admin" do
    request = leave(mon, mon + 2)
    take_out(request, mon, note: "")
    expect(flash[:alert]).to eq("A reason is required.")
    follow_redirect!
    take_out(request, mon + 5)
    expect(flash[:alert]).to eq("That day cannot be taken out of this leave.")
    follow_redirect!

    request.update!(decided_by_id: admin.id)
    take_out(request, mon)
    expect(flash[:alert]).to eq(HrLite::ADMIN_DECIDED)
    expect(request.reload.start_date).to eq(mon)

    sign_in admin
    take_out(request, mon)
    expect(request.reload.start_date).to eq(mon + 1)
  end
end
