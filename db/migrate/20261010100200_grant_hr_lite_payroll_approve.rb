class GrantHrLitePayrollApprove < ActiveRecord::Migration[8.1]
  # payroll.approve is new in 0.24.0, and RoleSeeds never touches an existing
  # role, so without this nobody on a running install could approve. HR and
  # Super Admin approve; HR also reads every run, sets salary structures and
  # edits employee profiles (owner decision 2026-10-09).
  GRANTS = {
    "HR" => { "payroll.approve" => "all", "payroll.view" => "all", "salary.view" => "all", "salary.manage" => "all", "profile.manage" => "all" },
    "Super Admin" => { "payroll.approve" => "all" }
  }.freeze

  def up
    GRANTS.each do |role_name, grants|
      role = HrLite::Role.find_by(name: role_name) or next
      grants.each do |key, scope|
        grant = HrLite::RoleGrant.find_or_initialize_by(role: role, permission_key: key)
        grant.update!(scope: scope)
      end
    end
  end

  def down; end
end
