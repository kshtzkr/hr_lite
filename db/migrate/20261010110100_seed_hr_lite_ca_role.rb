class SeedHrLiteCaRole < ActiveRecord::Migration[8.1]
  # The CA role is new in 0.26.0 and payroll.verify is a new key. RoleSeeds
  # creates the missing role; Super Admin, an existing role, gets the key here.
  def up
    return unless HrLite::Role.exists?

    require "hr_lite/role_seeds"
    HrLite::RoleSeeds.call
    super_admin = HrLite::Role.find_by(name: "Super Admin") or return
    HrLite::RoleGrant.find_or_initialize_by(role: super_admin, permission_key: "payroll.verify").update!(scope: "all")
  end

  def down; end
end
