module HrLite
  # One rung. The approver is named by RULE, not by person, so a flow
  # survives somebody leaving the company — the rule is resolved against the
  # subject at the moment the request is raised.
  class ApprovalStep < ApplicationRecord
    RULES = %w[manager manager_of_manager permission user].freeze

    belongs_to :flow, class_name: "HrLite::ApprovalFlow"

    validates :position, presence: true, uniqueness: { scope: :flow_id }
    validates :approver_rule, inclusion: { in: RULES }
    validates :sla_hours, numericality: { greater_than: 0 }, allow_nil: true
    validate :approver_key_matches_the_rule

    scope :ordered, -> { order(:position) }

    # Everybody who must (or may) decide this rung for `subject`. Empty means
    # nobody fits — `ApprovalRoute` treats that as a rung to skip rather than
    # a request nobody can ever answer.
    # Array(...) rather than an `else` arm: `approver_rule` is held to the
    # four RULES by a validation AND a database check constraint, so an
    # unmatched `case` cannot happen — and a defensive branch nothing can
    # reach is a line that never gets tested and quietly rots.
    def approvers_for(subject)
      Array(
        case approver_rule
        when "manager" then manager_of(subject.user_id)
        when "manager_of_manager" then manager_of(manager_of(subject.user_id)&.id)
        when "permission" then HrLite.users_holding(approver_key, scope: :all).to_a
        when "user" then HrLite.user_klass.find_by(id: approver_key)
        end
      )
    end

    def label
      case approver_rule
      when "manager" then "Their manager"
      when "manager_of_manager" then "Their manager's manager"
      when "permission" then "Anyone who can #{Permissions.description(approver_key).downcase}"
      when "user" then HrLite.display_name(HrLite.user_klass.find_by(id: approver_key))
      end
    end

    private

    def manager_of(user_id)
      return nil if user_id.nil?

      manager_id = EmployeeProfile.where(user_id: user_id).pick(:manager_id)
      manager_id && HrLite.user_klass.find_by(id: manager_id)
    end

    def approver_key_matches_the_rule
      case approver_rule
      when "permission"
        errors.add(:approver_key, "must be a known permission") unless Permissions.valid?(approver_key.to_s)
      when "user"
        errors.add(:approver_key, "must name a user") if approver_key.blank?
      end
    end
  end
end
