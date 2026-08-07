module HrLite
  # Append-only trail of every governing-tier mutation. Rows are never
  # updated or deleted; the leadership audit screen and the policy.changed
  # email diff both read from here.
  class AuditLog < ApplicationRecord
    belongs_to :actor, class_name: HrLite.config.user_class, optional: true
    belongs_to :subject, polymorphic: true, optional: true

    validates :action, :subject_type, :subject_id, presence: true

    # Subjects whose CONTENTS belong to the money tier. Salary structures
    # encrypt their amounts so the diff is already redacted, but appraisal
    # ratings and review text are plain columns — they must not reach the
    # leadership audit screen or the policy.changed email.
    MONEY_TIER_TYPES = %w[HrLite::Appraisal HrLite::DesignationChange HrLite::SalaryStructure].freeze

    scope :recent, -> { order(created_at: :desc) }
    scope :outside_money_tier, -> { where.not(subject_type: MONEY_TIER_TYPES) }

    def money_tier?
      MONEY_TIER_TYPES.include?(subject_type)
    end

    def readonly?
      persisted?
    end
  end
end
