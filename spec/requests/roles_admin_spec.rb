require "rails_helper"

RSpec.describe "Managing roles over HTTP", type: :request do
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  describe "who may reach it" do
    it "admits the holder of role.manage" do
      sign_in owner
      get "/hr/admin/roles"
      expect(response).to have_http_status(:ok)
    end

    # Running HR is not the same authority as deciding who runs HR.
    it "turns HR and employees away" do
      sign_in hr
      get "/hr/admin/roles"
      expect(response).to redirect_to("/hr/")

      sign_in employee
      get "/hr/admin/roles"
      expect(response).to redirect_to("/hr/")
    end
  end

  describe "editing a role" do
    it "replaces the whole grant set — an unticked permission is taken away" do
      sign_in owner
      role = HrLite::Role.find_by!(name: HrLite::Role::MANAGER)

      patch "/hr/admin/roles/#{role.id}", params: {
        role: { description: "Team leads" },
        grants: { "leave.approve" => "team", "attendance.view" => "all", "leave.view" => "none" }
      }

      expect(response).to redirect_to("/hr/admin/roles")
      expect(role.reload.grant_map)
        .to eq("leave.approve" => "team", "attendance.view" => "all")
      expect(role.description).to eq("Team leads")
    end

    it "refuses to rename a built-in role" do
      sign_in owner
      role = HrLite::Role.find_by!(name: HrLite::Role::HR)

      patch "/hr/admin/roles/#{role.id}", params: { role: { name: "People Ops" }, grants: {} }

      expect(role.reload.name).to eq(HrLite::Role::HR)
    end

    it "refuses to delete a built-in role" do
      sign_in owner
      role = HrLite::Role.find_by!(name: HrLite::Role::HR)

      delete "/hr/admin/roles/#{role.id}"

      expect(flash[:alert]).to include("built-in")
      expect(HrLite::Role.exists?(role.id)).to be(true)
    end

    it "creates and deletes a role of the install's own" do
      sign_in owner

      expect {
        post "/hr/admin/roles", params: {
          role: { name: "Auditor", description: "Reads, changes nothing" },
          grants: { "audit.view" => "all", "payroll.view" => "all" }
        }
      }.to change(HrLite::Role, :count).by(1)

      role = HrLite::Role.find_by!(name: "Auditor")
      expect(role.grant_map).to eq("audit.view" => "all", "payroll.view" => "all")
      expect(role).not_to be_system

      delete "/hr/admin/roles/#{role.id}"
      expect(HrLite::Role.exists?(role.id)).to be(false)
    end

    it "re-renders an invalid role rather than losing the form" do
      sign_in owner
      post "/hr/admin/roles", params: { role: { name: "" }, grants: {} }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "re-renders an invalid EDIT rather than losing the grants being set" do
      sign_in owner
      # An install's own role, so the name is editable and can be blanked.
      post "/hr/admin/roles", params: { role: { name: "Auditor" }, grants: { "audit.view" => "all" } }
      role = HrLite::Role.find_by!(name: "Auditor")

      patch "/hr/admin/roles/#{role.id}", params: { role: { name: "" }, grants: {} }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(role.reload.name).to eq("Auditor")
      expect(role.grant_map).to eq("audit.view" => "all")
    end

    it "renders the new and edit forms" do
      sign_in owner

      get "/hr/admin/roles/new"
      expect(response).to have_http_status(:ok)

      get "/hr/admin/roles/#{HrLite::Role.find_by!(name: HrLite::Role::MANAGER).id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Their team&#39;s records")
    end
  end

  describe "assigning people" do
    it "adds and removes somebody, and takes effect on the next request" do
      sign_in owner
      role = HrLite::Role.find_by!(name: HrLite::Role::HR)

      post "/hr/admin/roles/#{role.id}/assignments", params: { user_id: employee.id }
      expect(HrLite.admin?(employee.reload)).to be(true)

      assignment = HrLite::RoleAssignment.find_by!(user_id: employee.id, role_id: role.id)
      delete "/hr/admin/roles/#{role.id}/assignments/#{assignment.id}"
      HrLite::Current.access_cache = nil
      expect(HrLite.admin?(employee.reload)).to be(false)
    end

    it "says so rather than duplicating an assignment" do
      sign_in owner
      role = HrLite::Role.find_by!(name: HrLite::Role::HR)
      post "/hr/admin/roles/#{role.id}/assignments", params: { user_id: employee.id }
      post "/hr/admin/roles/#{role.id}/assignments", params: { user_id: employee.id }

      expect(flash[:alert]).to include("already hold")
      expect(HrLite::RoleAssignment.where(user_id: employee.id, role_id: role.id).count).to eq(1)
    end

    # Locking the last person out of role management cannot be undone from
    # inside the app — it would take a console.
    it "refuses to remove the only person who can manage roles" do
      sign_in owner
      role = HrLite::Role.find_by!(name: HrLite::Role::SUPER_ADMIN)
      assignment = HrLite::RoleAssignment.find_by!(user_id: owner.id, role_id: role.id)

      delete "/hr/admin/roles/#{role.id}/assignments/#{assignment.id}"

      expect(flash[:alert]).to include("only person who can manage roles")
      expect(HrLite::RoleAssignment.exists?(assignment.id)).to be(true)
    end

    it "allows the removal once somebody else can manage roles" do
      second = user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Second")
      sign_in owner
      role = HrLite::Role.find_by!(name: HrLite::Role::SUPER_ADMIN)
      assignment = HrLite::RoleAssignment.find_by!(user_id: second.id, role_id: role.id)

      delete "/hr/admin/roles/#{role.id}/assignments/#{assignment.id}"

      expect(HrLite::RoleAssignment.exists?(assignment.id)).to be(false)
    end
  end

  describe "the audit trail" do
    it "records who was given which role" do
      sign_in owner
      employee # created (and given Employee) before the count starts
      role = HrLite::Role.find_by!(name: HrLite::Role::FINANCE)

      expect {
        post "/hr/admin/roles/#{role.id}/assignments", params: { user_id: employee.id }
      }.to change { HrLite::AuditLog.where(subject_type: "HrLite::RoleAssignment").count }.by(1)
    end
  end
end
