module HrLite
  class LeaveRequest < ApplicationRecord
    STATUSES = %w[pending approved rejected cancelled].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :leave_type
    belongs_to :decided_by, class_name: HrLite.config.user_class, optional: true

    validates :start_date, :end_date, presence: true
    validates :status, inclusion: { in: STATUSES }

    with_options on: :create do
      validate :end_after_start
      validate :same_calendar_year
      validate :half_day_single_day_only
      validate :consumes_at_least_half_a_day
      validate :no_overlap_with_own_requests
      validate :no_punch_conflict
      validate :sufficient_balance
    end

    before_validation :cache_days_count, on: :create
    after_create :notify_requested

    scope :pending, -> { where(status: "pending") }
    scope :approved, -> { where(status: "approved") }
    scope :active_on, ->(date) { approved.where(start_date: ..date).where(end_date: date..) }
    scope :overlapping_range, ->(from, to) { where(start_date: ..to).where(end_date: from..) }
    scope :recent_first, -> { order(start_date: :desc, id: :desc) }

    STATUSES.each do |s|
      define_method("#{s}?") { status == s }
    end

    def paid?
      leave_type.paid
    end

    # --- transitions -------------------------------------------------------

    # Returns false (leaving the request pending) when the balance no longer
    # covers it — the re-check runs inside the row lock so two concurrent
    # approvals cannot overdraw one balance.
    def approve!(actor:, note: nil)
      insufficient = false
      transition!("approved", actor, note) do
        if insufficient_balance_now?
          insufficient = true
          raise ActiveRecord::Rollback
        end
      end
      return false if insufficient

      notify_decision("Leave approved")
      true
    end

    def reject!(actor:, note:)
      transition!("rejected", actor, note)
      notify_decision("Leave rejected")
      true
    end

    # Owner may cancel while pending, or an approved future leave (quota
    # returns automatically because `used` is computed). Admins may cancel
    # any pending/approved future leave.
    def cancellable_by?(actor)
      return false unless pending? || (approved? && start_date > Date.current)

      user_id == actor.id || HrLite.admin?(actor) || HrLite.leadership?(actor)
    end

    def cancel!(actor:)
      was_approved = approved?
      self.status = "cancelled"
      self.decided_by_id = actor.id
      self.decided_at = Time.current
      save!

      Notifications.publish(
        "leave.cancelled",
        title: "#{HrLite.display_name(user)} cancelled #{was_approved ? 'approved ' : ''}leave " \
               "(#{date_range_label})",
        path: "/admin/leave_requests",
        bell_to: HrLite.admin_users
      )
      true
    end

    def date_range_label
      if start_date == end_date
        "#{start_date.strftime('%d %b')}#{half_day ? ' (half day)' : ''}"
      else
        "#{start_date.strftime('%d %b')} – #{end_date.strftime('%d %b')}"
      end
    end

    def balance
      LeaveBalance.for(user, leave_type, start_date.year)
    end

    private

    def transition!(new_status, actor, note)
      with_lock do
        raise ActiveRecord::RecordInvalid.new(self), "not pending" unless pending?

        yield if block_given?
        self.status = new_status
        self.decided_by_id = actor.id
        self.decided_at = Time.current
        self.decision_note = note
        save!
      end
    end

    # This request is still pending here, so balance.used excludes it:
    # approving is valid iff the request fits the remaining balance.
    def insufficient_balance_now?
      return false if leave_type.unlimited?

      LeaveDayCounter.count(self) > balance.available
    end

    def notify_requested
      Notifications.publish(
        "leave.requested",
        title: "#{HrLite.display_name(user)} applied for #{leave_type.name} (#{date_range_label})",
        body: reason.presence,
        path: "/admin/leave_requests/#{id}",
        bell_to: HrLite.admin_users
      )
    end

    def notify_decision(title)
      Notifications.publish(
        status == "approved" ? "leave.approved" : "leave.rejected",
        title: "#{title} — #{leave_type.name} (#{date_range_label})",
        body: decision_note.presence,
        path: "/leave_requests/#{id}",
        bell_to: [ user ],
        email_to: [ user ]
      )
    end

    def cache_days_count
      self.days_count = LeaveDayCounter.count(self) if start_date && end_date
      self.days_count ||= 0
    end

    def end_after_start
      return unless start_date && end_date

      errors.add(:end_date, "must be on or after the start date") if end_date < start_date
    end

    def same_calendar_year
      return unless start_date && end_date

      if start_date.year != end_date.year
        errors.add(:base, "Split requests at the year boundary")
      end
    end

    def half_day_single_day_only
      errors.add(:half_day, "is only for single-day requests") if half_day && start_date != end_date
    end

    def consumes_at_least_half_a_day
      return unless start_date && end_date
      return if errors.any?

      if LeaveDayCounter.count(self) <= 0
        errors.add(:base, "Selected dates are all holidays or weekends")
      end
    end

    def no_overlap_with_own_requests
      return unless start_date && end_date

      clash = self.class.where(user_id: user_id, status: %w[pending approved])
                  .where.not(id: id)
                  .overlapping_range(start_date, end_date)
      errors.add(:base, "You already have leave overlapping these dates") if clash.exists?
    end

    # A full-day leave over a day that already has a check-in makes no
    # sense; a half-day alongside a punch is legitimate (worked half).
    def no_punch_conflict
      return unless start_date && end_date
      return if half_day

      punched = AttendanceRecord.where(user_id: user_id, date: start_date..end_date)
                                .where.not(check_in_at: nil)
      errors.add(:base, "You have marked attendance in this period") if punched.exists?
    end

    def sufficient_balance
      return unless start_date && end_date && leave_type
      return if leave_type.unlimited? || errors.any?

      if LeaveDayCounter.count(self) > balance.available(as_of: start_date)
        errors.add(:base, "Not enough #{leave_type.name} balance")
      end
    end
  end
end
