module HrLite
  # "I worked on a weekend/holiday — credit me a day off." Approval credits
  # the comp-off leave type's balance (an adjustment, so it shows up in the
  # normal balance chips and can be spent through the ordinary leave flow).
  class CompOffRequest < ApplicationRecord
    STATUSES = %w[pending approved rejected cancelled].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :decided_by, class_name: HrLite.config.user_class, optional: true

    validates :date_worked, :reason, presence: true
    validates :status, inclusion: { in: STATUSES }

    with_options on: :create do
      validate :date_not_in_future
      validate :date_was_an_off_day
      validate :no_duplicate_for_date
    end

    after_create :notify_requested

    scope :pending, -> { where(status: "pending") }
    scope :recent_first, -> { order(date_worked: :desc, id: :desc) }

    STATUSES.each do |s|
      define_method("#{s}?") { status == s }
    end

    def credit_days
      half_day ? BigDecimal("0.5") : BigDecimal("1")
    end

    # Shown to the approver: proof the person actually punched that day.
    def punch
      AttendanceRecord.find_by(user_id: user_id, date: date_worked)
    end

    # --- transitions -------------------------------------------------------

    # Credits the comp-off balance inside the row lock, so a double-tap
    # cannot credit twice. Fails loudly when no comp-off type is configured.
    def approve!(actor:, note: nil)
      type = LeaveType.comp_off_type
      raise MissingCompOffType if type.nil?

      transition!("approved", actor, note) do
        balance = LeaveBalance.for(user, type, date_worked.year)
        balance.adjustment += credit_days
        balance.adjustment_note = [ balance.adjustment_note.presence,
                                    "+#{credit_days.to_f} comp-off for #{date_worked} (request ##{id})" ].compact.join("; ")
        balance.save!
      end

      Notifications.publish(
        "comp_off.approved",
        title: "Comp-off approved — #{credit_days.to_f} day#{'s' if credit_days > 1} credited for #{date_worked.strftime('%d %b')}",
        body: decision_note.presence,
        path: "/comp_off_requests",
        bell_to: [ user ], email_to: [ user ]
      )
      true
    end

    def reject!(actor:, note:)
      transition!("rejected", actor, note)
      Notifications.publish(
        "comp_off.rejected",
        title: "Comp-off rejected — #{date_worked.strftime('%d %b')}",
        body: decision_note.presence,
        path: "/comp_off_requests",
        bell_to: [ user ], email_to: [ user ]
      )
      true
    end

    def cancel!(actor:)
      transition!("cancelled", actor, nil)
      Notifications.publish(
        "comp_off.cancelled",
        title: "#{HrLite.display_name(user)} cancelled a comp-off request (#{date_worked.strftime('%d %b')})",
        path: "/admin/comp_off_requests",
        bell_to: HrLite.admin_users
      )
      true
    end

    class MissingCompOffType < StandardError
      def message
        "No active leave type is marked as comp-off — enable one under Settings → Leave types first."
      end
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

    def date_not_in_future
      return unless date_worked

      errors.add(:date_worked, "cannot be in the future") if date_worked > Date.current
    end

    # Comp-off is for working on a day you were NOT supposed to — a weekend
    # or a holiday (per the company calendar). Extra hours on a working day
    # are not comp-off under the policy.
    def date_was_an_off_day
      return unless date_worked
      return if date_worked > Date.current

      calendar = WorkingCalendar.new(date_worked..date_worked)
      if calendar.working_day?(date_worked)
        errors.add(:date_worked, "was a regular working day — comp-off is for working on a weekend or holiday")
      end
    end

    def no_duplicate_for_date
      return unless date_worked

      clash = self.class.where(user_id: user_id, date_worked: date_worked,
                               status: %w[pending approved]).where.not(id: id)
      errors.add(:date_worked, "already has a comp-off request") if clash.exists?
    end

    def notify_requested
      Notifications.publish(
        "comp_off.requested",
        title: "#{HrLite.display_name(user)} requested comp-off for #{date_worked.strftime('%d %b')} " \
               "(#{half_day ? 'half' : 'full'} day)",
        body: reason.presence,
        path: "/admin/comp_off_requests/#{id}",
        bell_to: HrLite.admin_users
      )
    end
  end
end
