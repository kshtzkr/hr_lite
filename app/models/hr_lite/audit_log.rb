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
    MONEY_TIER_TYPES = %w[
      HrLite::Appraisal HrLite::DesignationChange HrLite::SalaryStructure
      HrLite::PayrollRun HrLite::SalarySlip
    ].freeze

    scope :recent, -> { order(created_at: :desc) }
    scope :outside_money_tier, -> { where.not(subject_type: MONEY_TIER_TYPES) }

    # The five-line `create!` that four call sites had each spelled out.
    #
    # This RAISES, unlike the Audited concern, which swallows failures so an
    # audit hiccup cannot roll back an ordinary policy edit. On the money
    # path that trade goes the other way: a payroll transition nobody can
    # explain afterwards should not be allowed to happen at all, so callers
    # run it inside the same transaction as the write it describes.
    #
    # `changes` is a whitelist the caller writes out by hand. Never pass
    # amounts — this table is not encrypted.
    def self.record!(action:, subject:, actor: HrLite::Current.actor, changes: {})
      create!(
        actor: actor,
        action: action,
        subject_type: subject.class.name,
        # A destroyed record has no id left, and the row still has to say
        # what happened.
        subject_id: subject.id || 0,
        audited_changes: changes
      )
    end

    def money_tier?
      MONEY_TIER_TYPES.include?(subject_type)
    end

    def readonly?
      persisted?
    end
  end
end
