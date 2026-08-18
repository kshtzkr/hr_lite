module HrLite
  # A claim. Routed through the approval engine rather than growing a fifth
  # approve/reject of its own — configure a flow for it and it gets manager
  # then finance for free.
  class Expense < ApplicationRecord
    include EncryptedMoney
    include Audited
    include Approvable

    STATUSES = %w[draft submitted approved rejected reimbursed cancelled].freeze

    encrypted_money :amount

    belongs_to :category, class_name: "HrLite::ExpenseCategory"
    belongs_to :user, class_name: HrLite.config.user_class

    has_one_attached :receipt

    validates :status, inclusion: { in: STATUSES }
    validates :description, presence: true
    validates :spent_on, presence: true
    validate :amount_is_positive
    validate :spent_on_is_not_in_the_future
    validate :within_the_category_cap, on: :create
    validate :receipt_is_present_when_the_category_demands_one

    scope :awaiting_reimbursement, -> { where(status: "approved") }
    scope :recent_first, -> { order(spent_on: :desc, id: :desc) }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    def submit!(actor:)
      raise ActiveRecord::RecordInvalid.new(self), "not a draft" unless draft? || rejected?

      update!(status: "submitted", submitted_at: Time.current)
      notify_deciders
      true
    end

    def approve!(actor:, note: nil)
      return record_routed!(actor, note, :approved) if awaiting?(actor)

      settle!("approved", actor, note)
    end

    def reject!(actor:, note:)
      raise ArgumentError, "a rejection needs a reason" if note.blank?
      return record_routed!(actor, note, :rejected) if awaiting?(actor)

      settle!("rejected", actor, note)
    end

    # Paid out with a payroll month. Kept separate from `approved` because
    # agreeing to pay somebody and actually paying them are different days,
    # and the person waiting cares about the second one.
    def reimburse!(actor:, period_month:)
      raise ActiveRecord::RecordInvalid.new(self), "not approved" unless approved?

      transaction do
        update!(status: "reimbursed", reimbursed_in: period_month.beginning_of_month)
        AuditLog.record!(action: "expense.reimbursed", subject: self, actor: actor,
                         changes: { "employee" => HrLite.display_name(user),
                                    "period" => period_month.strftime("%B %Y") })
      end
      Notifications.publish(
        "expense.reimbursed",
        title: "Your #{category.name} claim was reimbursed with #{period_month.strftime('%B %Y')} payroll",
        path: "/expenses", bell_to: [ user ], email_to: [ user ]
      )
      true
    end

    private

    def record_routed!(actor, note, intent)
      approval = approval_for(actor)
      result = approval_route.decide!(approval, status: intent.to_s, actor: actor, note: note)

      case result.outcome
      when :approved then settle!("approved", actor, note)
      # `reject!` already refuses a blank note, so there is nothing to
      # default to here.
      when :rejected then settle!("rejected", actor, note)
      else
        notify_deciders
        true
      end
    end

    def settle!(new_status, actor, note)
      update!(status: new_status, decision_note: note.presence)
      Notifications.publish(
        new_status == "approved" ? "expense.approved" : "expense.rejected",
        title: "Your #{category.name} claim was #{new_status}",
        body: note.presence, path: "/expenses", bell_to: [ user ], email_to: [ user ]
      )
      true
    end

    def notify_deciders
      deciders = pending_approvals.map(&:approver).compact.uniq
      deciders = HrLite.users_holding("expense.approve").to_a if deciders.empty?
      return if deciders.empty?

      Notifications.publish(
        "expense.submitted",
        title: "#{HrLite.display_name(user)} claimed #{Money.format(amount)} — #{category.name}",
        body: description, path: "/admin/expenses", bell_to: deciders
      )
    end

    def amount_is_positive
      errors.add(:amount, "must be more than zero") unless amount&.positive?
    end

    def spent_on_is_not_in_the_future
      return if spent_on.nil? || spent_on <= Date.current

      errors.add(:spent_on, "cannot be in the future")
    end

    # Checked at claim time rather than at approval: telling somebody they
    # are over the cap after they have waited a week for an answer is the
    # wrong moment to find out.
    def within_the_category_cap
      return if category.nil? || amount.nil? || spent_on.nil?

      remaining = category.remaining_for(user, spent_on.beginning_of_month)
      return if remaining.nil? || amount <= remaining

      errors.add(:amount, "is over the #{category.name} cap for #{spent_on.strftime('%B')} " \
                          "— #{Money.format(remaining)} left")
    end

    def receipt_is_present_when_the_category_demands_one
      return unless category&.receipt_required
      return if receipt.attached?

      errors.add(:receipt, "is required for #{category.name}")
    end
  end
end
