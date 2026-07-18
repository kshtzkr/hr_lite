module HrLite
  # Append-only trail of every governing-tier mutation. Rows are never
  # updated or deleted; the leadership audit screen and the policy.changed
  # email diff both read from here.
  class AuditLog < ApplicationRecord
    belongs_to :actor, class_name: HrLite.config.user_class, optional: true
    belongs_to :subject, polymorphic: true, optional: true

    validates :action, :subject_type, :subject_id, presence: true

    scope :recent, -> { order(created_at: :desc) }

    def readonly?
      persisted?
    end
  end
end
