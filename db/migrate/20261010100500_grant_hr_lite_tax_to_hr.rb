class GrantHrLiteTaxToHr < ActiveRecord::Migration[8.1]
  # HR sees and checks everyone's tax (owner decision 2026-10-09). RoleSeeds
  # never touches an existing role, so a running install needs this.
  def up
    role = HrLite::Role.find_by(name: "HR") or return
    { "tax.view" => "all", "tax.manage" => "all" }.each do |key, scope|
      HrLite::RoleGrant.find_or_initialize_by(role: role, permission_key: key).update!(scope: scope)
    end
  end

  def down; end
end
