module HrLite
  # A performance improvement plan. Super Admin writes it (the appraisal
  # tier); the employee is told when it starts and when it closes. Closing as
  # passed or failed stamps closed_at and freezes the row.
  class PerformancePlan < ApplicationRecord
    include Audited

    STATUSES = %w[active extended passed failed].freeze
    CLOSED = %w[passed failed].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :created_by, class_name: HrLite.config.user_class, optional: true

    validates :start_date, :end_date, :goals, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :ends_after_start

    scope :open_first, -> { order(Arel.sql("CASE WHEN status IN ('active', 'extended') THEN 0 ELSE 1 END"), :end_date) }

    before_save { self.closed_at ||= Time.current if closed? }
    after_create_commit { notify("pip.started", "Performance improvement plan started", "Runs until #{end_date.strftime('%d %b %Y')}.") }
    after_update_commit do
      notify("pip.closed", "Performance improvement plan #{status}", outcome_note) if saved_change_to_status? && closed?
    end

    def closed? = CLOSED.include?(status)

    # A closed plan is the record of its outcome.
    def readonly?
      persisted? && CLOSED.include?(status_in_database) && !destroyed?
    end

    private

    def ends_after_start
      errors.add(:end_date, "must be after the start date") if start_date && end_date && end_date <= start_date
    end

    def notify(event, title, body)
      Notifications.publish(event, title: title, body: body.presence, path: "/timeline", bell_to: [ user ], email_to: [ user ])
    end
  end
end
