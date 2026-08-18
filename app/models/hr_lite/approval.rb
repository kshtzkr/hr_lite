module HrLite
  # One person's outstanding decision on one record. The row is the unit the
  # inbox lists and the escalation job reads.
  class Approval < ApplicationRecord
    STATUSES = %w[pending approved rejected returned skipped cancelled].freeze

    belongs_to :step, class_name: "HrLite::ApprovalStep"
    belongs_to :subject, polymorphic: true
    belongs_to :approver, class_name: HrLite.config.user_class
    belongs_to :decided_by, class_name: HrLite.config.user_class, optional: true

    validates :status, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: "pending") }
    scope :at_position, ->(position) { where(position: position) }
    scope :recent_first, -> { order(created_at: :desc) }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    # Whether `user` may answer this — the approver themselves, or somebody
    # they have delegated to while they are away.
    def answerable_by?(user)
      return false if user.nil? || !pending?

      approver_id == user.id ||
        ApprovalDelegation.stand_ins_for(approver_id).include?(user.id)
    end

    def decide!(status:, actor:, note: nil)
      raise ArgumentError, "unknown decision #{status}" unless STATUSES.include?(status.to_s)

      update!(status: status.to_s, note: note.presence, decided_at: Time.current,
              decided_by_id: actor&.id)
    end

    # True once this row's SLA has run out. Computed rather than stored so
    # editing a step's SLA takes effect on the rows already waiting.
    def overdue?(now = Time.current)
      return false unless pending? && step.sla_hours

      created_at + step.sla_hours.hours <= now
    end

    def label = "#{subject_type.demodulize.underscore.humanize} ##{subject_id}"
  end
end
