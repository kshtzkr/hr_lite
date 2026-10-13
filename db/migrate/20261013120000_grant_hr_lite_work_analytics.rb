class GrantHrLiteWorkAnalytics < ActiveRecord::Migration[8.1]
  # work_analytics.view is new in 0.31.0. RoleSeeds only creates missing
  # roles, so the existing HR, Leadership and Super Admin roles get it here.
  # Manager deliberately does not.
  def up
    return unless HrLite::Role.exists?

    HrLite::Role.where(name: [ "HR", "Leadership", "Super Admin" ]).find_each do |role|
      HrLite::RoleGrant.find_or_initialize_by(role: role, permission_key: "work_analytics.view").update!(scope: "all")
    end
  end

  def down; end
end
