class BackfillHrLiteEnforcedPermissionKeys < ActiveRecord::Migration[8.1]
  # 0.70.0 starts checking five keys that the screens never asked for. Every
  # role keeps the access it has today: it gets the new key wherever it holds
  # the key that opened the screen before.
  NEW_KEYS = {
    "profile.manage" => %w[audit.view settings.manage resignation.manage],
    "payroll.manage" => %w[audit.view_money],
    "expense.approve" => %w[expense.reimburse]
  }.freeze

  def up
    NEW_KEYS.each do |held, keys|
      HrLite::RoleGrant.where(permission_key: held, scope: "all").pluck(:role_id).each do |role_id|
        keys.each { |key| HrLite::RoleGrant.find_or_initialize_by(role_id: role_id, permission_key: key).update!(scope: "all") }
      end
    end
  end

  def down; end
end
