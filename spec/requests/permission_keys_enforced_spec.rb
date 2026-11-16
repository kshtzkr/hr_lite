require "rails_helper"

# The five registry keys no screen used to ask for (security audit 2026-11).
RSpec.describe "Permission keys are enforced", type: :request do
  let(:role) { HrLite::Role.create!(name: "People only").tap { |r| r.replace_grants!("profile.manage" => "all") } }
  let(:hr) { create(:user).tap { |u| HrLite::RoleAssignment.insert_all([ { user_id: u.id, role_id: role.id, created_at: Time.current, updated_at: Time.current } ]) } }

  def grant(_user, key) = HrLite::RoleGrant.create!(role: role, permission_key: key, scope: "all")

  { "/hr/admin/audit_logs" => "audit.view", "/hr/admin/setting/edit" => "settings.manage",
    "/hr/admin/office_locations" => "settings.manage", "/hr/admin/expense_categories" => "settings.manage" }.each do |path, key|
    it "opens #{path} on #{key}, not on profile.manage" do
      sign_in hr
      get path
      expect(response).not_to have_http_status(:ok)

      grant(hr, key)
      get path
      expect(response).to have_http_status(:ok)
    end
  end
end
