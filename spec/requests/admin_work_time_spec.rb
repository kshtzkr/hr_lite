require "rails_helper"

RSpec.describe "HR work time", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:asha) { create(:user, name: "Asha") }
  let(:dev) { create(:user, name: "Dev") }
  let(:day) { Date.new(2026, 10, 20) }

  def t(hour) = Time.zone.local(2026, 10, 20, hour)
  def ev(user, mode, from, to) = HrLite::WorkModeEvent.create!(user_id: user.id, mode: mode, source: "system", started_at: from, ended_at: to)

  before do
    HrLite.config.office_geofence = true
    travel_to(t(20))
    create(:employee_profile, user: asha, department: "Sales")
    create(:employee_profile, user: dev, department: "Ops")
    create(:attendance_record, user: asha, date: day, check_in_at: t(9), check_out_at: t(18))
    ev(asha, "office", t(9), t(18))
    create(:attendance_record, user: dev, date: day, check_in_at: t(10), check_out_at: t(16))
    ev(dev, "wfh", t(10), t(16))
  end

  after { travel_back }

  it "keeps employees and managers without the permission out" do
    sign_in dev
    get "/hr/admin/work_time"
    expect(response).to redirect_to("/hr/")

    manager = user_with_roles(HrLite::Role::MANAGER, name: "Mona")
    HrLite::EmployeeProfile.find_by(user_id: asha.id).update!(manager_id: manager.id)
    sign_in manager
    get "/hr/admin/work_time", params: { user_id: asha.id }
    expect(response).to redirect_to("/hr/")
  end

  it "shows one person's analytics and writes the view to the audit trail" do
    sign_in admin
    get "/hr/admin/work_time", params: { user_id: asha.id, period: "day", date: day }
    expect(response.body).to include("Work time — Asha").and include("9h 00m").and include("The day, hour by hour")
    expect(HrLite::AuditLog.where(action: "work_analytics.viewed", subject_id: asha.id).count).to eq(1)
  end

  it "adds up a department, without per-person timelines" do
    sign_in admin
    get "/hr/admin/work_time", params: { period: "day", date: day }
    expect(response.body).to include("15h 00m") # 9h office + 6h WFH
    expect(response.body).not_to include("The day, hour by hour")
    get "/hr/admin/work_time", params: { period: "day", date: day, department: "Ops" }
    expect(response.body).to include("6h 00m")
    expect(HrLite::AuditLog.where(action: "work_analytics.viewed").count).to eq(0)
  end

  it "lets a manager granted the permission at team scope see only their reports" do
    manager = user_with_roles(HrLite::Role::MANAGER, name: "Mona")
    HrLite::Role.find_by(name: HrLite::Role::MANAGER).role_grants.create!(permission_key: "work_analytics.view", scope: "team")
    HrLite::EmployeeProfile.find_by(user_id: asha.id).update!(manager_id: manager.id)
    sign_in manager
    get "/hr/admin/work_time", params: { user_id: asha.id, period: "day", date: day }
    expect(response.body).to include("9h 00m")
    get "/hr/admin/work_time", params: { user_id: dev.id, period: "day", date: day }
    expect(response).to have_http_status(:not_found)
  end
end
