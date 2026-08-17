module HrLite
  # One (role, permission, scope) triple. The permission key is validated
  # against the declared registry, so a typo is a refused write rather than a
  # grant that silently never matches anything.
  class RoleGrant < ApplicationRecord
    belongs_to :role

    validates :permission_key, presence: true,
                               inclusion: { in: Permissions::KEYS, message: "is not a known permission" },
                               uniqueness: { scope: :role_id }
    validates :scope, inclusion: { in: Permissions::SCOPES.map(&:to_s) }

    def covers?(needed_scope) = Permissions.scope_covers?(scope, needed_scope)
  end
end
