module HrLite
  # Who holds which role. Assignments are audited because granting somebody
  # the money tier is exactly the kind of change that has to be explainable
  # afterwards.
  class RoleAssignment < ApplicationRecord
    include Audited

    belongs_to :role
    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :granted_by, class_name: HrLite.config.user_class, optional: true

    validates :user_id, uniqueness: { scope: :role_id }

    scope :for_user, ->(user) { where(user_id: user.id) }

    def hr_lite_audit_label = "#{HrLite.display_name(user)} — #{role.name}"
  end
end
