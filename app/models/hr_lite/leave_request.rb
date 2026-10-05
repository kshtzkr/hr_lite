module HrLite
  class LeaveRequest < ApplicationRecord
    include Approvable

    STATUSES = %w[pending approved rejected cancelled].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :leave_type
    belongs_to :decided_by, class_name: HrLite.config.user_class, optional: true
    # Set when HR records leave the employee forgot to apply for.
    belongs_to :created_by, class_name: HrLite.config.user_class, optional: true

    validates :start_date, :end_date, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :half_day_part, inclusion: { in: %w[first second] }, allow_blank: true

    with_options on: :create do
      validate :end_after_start
      validate :same_leave_year
      validate :half_day_single_day_only
      validate :consumes_at_least_half_a_day
      validate :no_overlap_with_own_requests
      validate :no_punch_conflict
      validate :sufficient_balance
      validate :within_probation_cap
    end

    before_validation { self.half_day = true if half_day_part.present? }
    before_validation :cache_days_count, on: :create
    after_create :notify_requested, unless: :recorded_by_hr?
    after_create :notify_team

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

    # Days this request would take past the balance — the loss of pay
    # approving it today would fix, or did fix once approved. 0 for unlimited types.
    def days_beyond_balance
      return 0 if leave_type.unlimited?
      return paid_days ? LeaveDayCounter.count(self) - paid_days : 0 if approved?

      [ LeaveDayCounter.count(self) - covered_by(balance.available(as_of: start_date)), 0 ].max
    end

    # Unpaid share (0, 0.5 or 1) of `date`: the balance covered the leave's
    # EARLIEST working days (paid_days of them), so the rest are loss of pay.
    def unpaid_on(date)
      return 0 if paid_days.nil?

      @leave_calendar ||= WorkingCalendar.new(start_date..end_date)
      through = LeaveDayCounter.count_range(start_date: start_date, end_date: date, half_day: half_day,
                                            calendar: @leave_calendar)
      (through - paid_days).clamp(0, half_day ? BigDecimal("0.5") : 1)
    end

    # --- transitions -------------------------------------------------------

    # With a flow configured this is ONE RUNG: the request becomes `approved`
    # only once the last rung is satisfied. With no flow — or from somebody
    # the flow is not waiting on, such as HR overriding — the first approval
    # settles it, exactly as before.
    #
    # Days beyond the balance are approved as loss of pay (paid_days); only
    # comp-off returns false (still pending) when its credit no longer covers
    # it. The balance is read inside the row lock, so two concurrent
    # approvals cannot both spend it.
    def approve!(actor:, note: nil)
      return record_routed_decision!(actor, note, :approved) if awaiting?(actor)

      approve_outright!(actor: actor, note: note)
    end

    def reject!(actor:, note:)
      return record_routed_decision!(actor, note, :rejected) if awaiting?(actor)

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
      transaction do
        self.status = "cancelled"
        self.decided_by_id = actor.id
        self.decided_at = Time.current
        save!
        # Cancelling an APPROVED leave hands the days back to the balance, so
        # it is a quota change as much as a status change.
        audit!("cancelled", actor, was_approved ? "was approved" : nil)
        # And nobody should still be asked to decide a request that has been
        # called off — it would sit in their inbox for ever.
        approval_route.cancel_all!
      end

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
        "#{start_date.strftime('%d %b')}#{half_day ? " (#{half_day_part.present? ? "#{half_day_part} half" : 'half day'})" : ''}"
      else
        "#{start_date.strftime('%d %b')} – #{end_date.strftime('%d %b')}"
      end
    end

    def balance
      LeaveBalance.for(user, leave_type, LeaveYear.key_for(start_date))
    end

    private

    # One rung answered. The route says whether that settles the request; if
    # it does, the ordinary transition runs and does the real work — crediting
    # or releasing balance, notifying, auditing — so routing never becomes a
    # second path that can drift from the first.
    def record_routed_decision!(actor, note, intent)
      approval = approval_for(actor)
      result = approval_route.decide!(approval, status: intent.to_s, actor: actor, note: note)

      case result.outcome
      when :approved then approve_outright!(actor: actor, note: note)
      when :rejected then reject_outright!(actor: actor, note: note.presence || "Rejected")
      else
        notify_pending_approvers
        true
      end
    end

    def approve_outright!(actor:, note:)
      insufficient = false
      transition!("approved", actor, note) do
        next if leave_type.unlimited?

        # Serialize on the BALANCE row. `transition!`'s own lock is on this
        # request, and two pending requests are two different rows — so both
        # approvals could read the same untouched balance and overdraw it.
        # As of start_date: the same date the create-time check uses.
        covered = covered_by(LeaveBalance.lock_for(user, leave_type, LeaveYear.key_for(start_date)).available(as_of: start_date))
        next if LeaveDayCounter.count(self) <= covered

        if leave_type.comp_off
          insufficient = true
          raise ActiveRecord::Rollback
        end
        self.paid_days = covered
      end
      return false if insufficient

      notify_decision("Leave approved")
      true
    end

    def reject_outright!(actor:, note:)
      transition!("rejected", actor, note)
      notify_decision("Leave rejected")
      true
    end

    # The next rung has just opened; tell the people it opened on.
    def notify_pending_approvers
      approvers = pending_approvals.map(&:approver).compact.uniq
      return if approvers.empty?

      Notifications.publish(
        "leave.requested",
        title: "#{HrLite.display_name(user)} — #{leave_type.name} (#{date_range_label}) needs your approval",
        body: reason.presence,
        path: "/admin/leave_requests/#{id}",
        bell_to: approvers
      )
    end

    def transition!(new_status, actor, note)
      with_lock do
        raise ActiveRecord::RecordInvalid.new(self), "not pending" unless pending?

        yield if block_given?
        self.status = new_status
        self.decided_by_id = actor.id
        self.decided_at = Time.current
        self.decision_note = note
        save!
        audit!(new_status, actor, note)
      end
    end

    # Approve and reject both come through `transition!`, and `with_lock` is
    # already a transaction — so a failed audit row rolls the decision back
    # rather than leaving one that nobody can account for. The employee's own
    # `reason` is deliberately not copied here; the approver's note is.
    def audit!(action, actor, note)
      AuditLog.record!(
        action: "leave.#{action}", subject: self, actor: actor,
        changes: {
          "employee" => HrLite.display_name(user),
          "type" => leave_type.code,
          "dates" => date_range_label,
          "days" => days_count&.to_s("F"),
          "paid_days" => paid_days&.to_s("F"),
          "note" => note.presence
        }.compact
      )
    end

    def recorded_by_hr? = created_by_id.present? && created_by_id != user_id

    # The balance covers whole half-days only, never less than nothing.
    def covered_by(available) = [ (BigDecimal(available.to_s) * 2).floor / BigDecimal(2), 0 ].max

    # Recorded leave is approved in the same transaction, so there is nothing
    # left for a flow to route.
    def open_approval_route = pending? && super

    def notify_requested
      Notifications.publish(
        "leave.requested",
        title: "#{HrLite.display_name(user)} applied for #{leave_type.name} (#{date_range_label})",
        body: reason.presence,
        path: "/admin/leave_requests/#{id}",
        bell_to: HrLite.admin_users,
        email_to: HrLite.admin_users
      )
    end

    # Everyone should know a colleague will be away, the moment they apply —
    # bell + email to the whole team (matrix row "leave.team_notice"; hosts can mute either
    # channel). Deliberately excludes the reason: dates are team-relevant,
    # the why is not.
    def notify_team
      return if end_date < Date.current # nobody needs to hear who was out

      team = HrLite.active_employees.reject { |member| member.id == user_id }
      return if team.empty?

      Notifications.publish(
        "leave.team_notice",
        title: "#{HrLite.display_name(user)} is on leave — #{leave_type.name} (#{date_range_label})",
        path: "/team",
        bell_to: team,
        email_to: team
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

    def same_leave_year
      return unless start_date && end_date

      if LeaveYear.key_for(start_date) != LeaveYear.key_for(end_date)
        errors.add(:base, "Split requests at the leave-year boundary")
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
      errors.add(:base, "Leave already overlaps these dates") if clash.exists?
    end

    # A full-day leave over a day that already has a check-in makes no
    # sense; a half-day alongside a punch is legitimate (worked half).
    def no_punch_conflict
      return unless start_date && end_date
      return if half_day

      punched = AttendanceRecord.where(user_id: user_id, date: start_date..end_date)
                                .where.not(check_in_at: nil)
      errors.add(:base, "Attendance is marked in this period") if punched.exists?
    end

    # Probation: at most one day of leave (any type) in a calendar month.
    def within_probation_cap
      return unless start_date && days_count
      return unless EmployeeProfile.find_by(user_id: user_id)&.on_probation?(start_date)

      taken = self.class.where(user_id: user_id, status: %w[pending approved])
                  .where(start_date: start_date.all_month).sum(:days_count)
      errors.add(:base, "During probation only 1 day of leave a month is allowed") if taken + days_count > 1
    end

    # Only comp-off is refused past its balance: it is earned credit, never
    # borrowed. Any other type's excess becomes loss of pay at approval.
    def sufficient_balance
      return unless start_date && end_date && leave_type
      return if leave_type.unlimited? || !leave_type.comp_off || errors.any?

      if LeaveDayCounter.count(self) > balance.available(as_of: start_date)
        errors.add(:base, "Not enough #{leave_type.name} balance")
      end
    end
  end
end
