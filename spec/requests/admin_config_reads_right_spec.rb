require "rails_helper"

# HRMS audit lane D1: admin configuration screens say what they mean on a phone.
RSpec.describe "Admin configuration screens read right", type: :request do
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  before { sign_in owner }

  it "hides page-view noise and humanises the audit trail (AD-6, VS-21)" do
    HrLite::AuditLog.record!(action: "work_analytics.viewed", subject: meera, actor: owner)
    HrLite::AuditLog.record!(action: "setting.updated", subject: meera, actor: nil, changes: { "day_minutes" => [ nil, 510 ] })
    get "/hr/admin/audit_logs"
    expect(response.body).to include("Setting updated", "System", "blank → 510", "Show page views too")
    expect(response.body).not_to include("Work analytics viewed", "nil")
    get "/hr/admin/audit_logs", params: { views: 1 }
    expect(response.body).to include("Work analytics viewed")
  end

  it "shows quotas in days with the leave colour as a dot, and Delete below the form (GL-6, VS-16)" do
    type = HrLite::LeaveType.create!(name: "Casual", code: "CL", annual_quota: 12, color: "#0ea5e9")
    get "/hr/admin/leave_types"
    expect(response.body).to include("12 days", 'class="hrl-badge hrl-badge--type" style="--hrl-type: #0ea5e9"')
    get "/hr/admin/leave_types/#{type.id}/edit"
    expect(response.body.index("Delete this leave type?")).to be > response.body.index("<form")
  end

  it "groups HR settings and names the weekly off in words (VS-15)" do
    get "/hr/admin/setting/edit"
    expect(response.body).to include("Working week", "Breaks", "Working day", "Saturday and Sunday")
  end

  it "folds each permission group behind its granted count (VS-11)" do
    role = HrLite::Role.create!(name: "Desk")
    role.role_grants.create!(permission_key: "leave.approve", scope: "team")
    get "/hr/admin/roles/#{role.id}/edit"
    expect(response.body).to match(%r{<details class="hrl-card" open>\s*<summary class="hrl-btn hrl-btn--block">[^<]+ · 1 of \d+ granted</summary>})
  end

  it "names who still has to acknowledge a policy (VS-12)" do
    meera
    HrLite::Policy.create!(title: "Leave policy", version: 1, body: "Read me", effective_from: Date.current,
                           acknowledgement_required: true, published: true)
    get "/hr/admin/policies"
    expect(response.body).to match(%r{<summary class="hrl-btn">\d+ (person|people)</summary>}).and include("Meera")
  end

  it "says when nothing is on file and labels every note and picker (VS-18, AD-7)" do
    get "/hr/admin/documents"
    expect(response.body).to include("No documents on file yet.")
    HrLite::Asset.create!(name: "Laptop", category: "laptop")
    get "/hr/admin/assets"
    expect(response.body).to include("Hand over to", "Choose…")
  end

  it "starts the balance picker blank and asks before changing a balance (AD-8)" do
    get "/hr/admin/leave_balances"
    expect(response.body).to include('<option value="">Choose…</option>', "Change this leave balance?")
  end
end
