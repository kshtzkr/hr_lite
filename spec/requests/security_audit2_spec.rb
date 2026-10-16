require "rails_helper"

# Second security pass (2026-10-16): self-edits, expiring file links and the
# audit trail. Each example is the refusal, the redaction or the row.
RSpec.describe "Security audit 2", type: :request do
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:boss) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }

  def pdf = { io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "scan.pdf", content_type: "application/pdf" }
  def actions = HrLite::AuditLog.pluck(:action)

  it "404s HR editing, re-paying or offboarding their own profile (SE-1)" do
    own = create(:employee_profile, user: hr, permanent_wfh: false)
    sign_in hr

    patch "/hr/admin/employees/#{own.id}", params: { employee_profile: { permanent_wfh: "1" } }
    expect(response).to have_http_status(:not_found)
    get "/hr/admin/employees/#{own.id}/salary_structures/new"
    expect(response).to have_http_status(:not_found)
    post "/hr/admin/employees/#{own.id}/offboard"
    expect(response).to have_http_status(:not_found)
    expect(own.reload).to have_attributes(permanent_wfh: false, date_of_exit: nil)
  end

  it "takes away everything but the Employee role on offboarding (SE-15)" do
    leaver = user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::FINANCE, name: "Leaver")
    profile = create(:employee_profile, user: leaver)
    sign_in hr

    post "/hr/admin/employees/#{profile.id}/offboard"
    expect(HrLite::RoleAssignment.for_user(leaver).map { |a| a.role.name }).to eq([ HrLite::Role::EMPLOYEE ])
  end
end
