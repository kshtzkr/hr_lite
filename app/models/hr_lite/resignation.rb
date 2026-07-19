module HrLite
  # Employee-initiated exit. One open resignation per person; accepting it
  # stamps the employee profile's exit date (which payroll and attendance
  # already respect) and notifies both sides. Withdrawal is allowed while
  # pending — leaving should never need an email thread.
  class Resignation < ApplicationRecord
    STATUSES = %w[pending accepted withdrawn].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :decided_by, class_name: HrLite.config.user_class, optional: true

    validates :proposed_last_day, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :last_day_not_past, on: :create
    validate :single_open_resignation, on: :create

    scope :pending, -> { where(status: "pending") }
    scope :recent_first, -> { order(created_at: :desc) }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    after_create :notify_submitted

    def accept!(actor:, last_day: nil, note: nil)
      raise ActiveRecord::RecordInvalid.new(self), "not pending" unless pending?

      final_day = last_day.presence || proposed_last_day
      transaction do
        update!(status: "accepted", decided_by_id: actor.id, decided_at: Time.current,
                decision_note: note.presence, proposed_last_day: final_day)
        profile = EmployeeProfile.find_by(user_id: user_id)
        profile&.update!(date_of_exit: final_day)
      end

      Notifications.publish(
        "resignation.accepted",
        title: "Resignation accepted — last working day #{final_day.strftime('%d %b %Y')}",
        body: note.presence,
        path: "/resignation",
        bell_to: [ user ],
        email_to: [ user ]
      )
      true
    end

    def withdraw!(actor:)
      raise ActiveRecord::RecordInvalid.new(self), "not pending" unless pending? && actor.id == user_id

      update!(status: "withdrawn", decided_at: Time.current)
      Notifications.publish(
        "resignation.withdrawn",
        title: "#{HrLite.display_name(user)} withdrew their resignation",
        path: "/admin/employees",
        bell_to: HrLite.admin_users
      )
      true
    end

    private

    def notify_submitted
      Notifications.publish(
        "resignation.submitted",
        title: "#{HrLite.display_name(user)} submitted their resignation " \
               "(last day proposed: #{proposed_last_day.strftime('%d %b %Y')})",
        body: reason.presence,
        path: "/admin/employees",
        bell_to: HrLite.admin_users
      )
    end

    def last_day_not_past
      return unless proposed_last_day

      errors.add(:proposed_last_day, "cannot be in the past") if proposed_last_day < Date.current
    end

    def single_open_resignation
      if self.class.pending.where(user_id: user_id).exists?
        errors.add(:base, "You already have a pending resignation")
      end
    end
  end
end
