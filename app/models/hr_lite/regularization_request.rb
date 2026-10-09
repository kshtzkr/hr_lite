module HrLite
  # "I forgot to punch — please fix that day." The employee proposes the
  # times; an admin approves, which applies them to the attendance record
  # with the full regularization audit trail (same fields the manual admin
  # fix writes), or rejects with a note.
  class RegularizationRequest < ApplicationRecord
    STATUSES = %w[pending approved rejected cancelled].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :decided_by, class_name: HrLite.config.user_class, optional: true

    validates :date, :reason, presence: true
    validates :status, inclusion: { in: STATUSES }

    with_options on: :create do
      validate :date_not_in_future
      validate :at_least_one_time
      validate :times_fall_on_date
      validate :checkout_after_checkin
      validate :no_duplicate_pending
      validate :no_approved_leave_conflict
    end

    after_create :self_fix_or_notify

    scope :pending, -> { where(status: "pending") }
    scope :recent_first, -> { order(date: :desc, id: :desc) }

    STATUSES.each do |s|
      define_method("#{s}?") { status == s }
    end

    def times_label
      [ check_in_at&.strftime("%H:%M"), check_out_at&.strftime("%H:%M") ].compact.join(" – ").presence || "Short day"
    end

    # Current punch state for the approver's context.
    def punch
      AttendanceRecord.find_by(user_id: user_id, date: date)
    end

    # config.self_regularization: a missed punch on a recent working day, under
    # the weekly cap, is fixed by the employee without HR. A real punch, or a
    # day HR already decided or rejected, stays HR's call.
    def self_fixable?
      rule = HrLite.config.self_regularization
      return false unless rule && date >= Date.current - rule[:within_days] && WorkingCalendar.new(date..date).working_day?(date)

      day = punch
      fills_gap = (check_in_at.nil? || !day&.check_in_at) &&
                  (check_out_at.nil? || !day&.check_out_at || day.regularization_note == AttendanceRecord::AUTO_CHECKOUT_NOTE)
      (fills_gap || short_day_ticket?) && !day&.regularized? && !self.class.exists?(user_id: user_id, date: date, status: "rejected") &&
        self_fixes_left.positive?
    end

    # No times, just a reason: "my hours were short that day, accept them".
    def short_day_ticket?
      check_in_at.nil? && check_out_at.nil? && !!punch&.short?
    end

    # Self-fixes the user still has in this ticket's Mon–Sun week.
    def self_fixes_left
      week = date.beginning_of_week(:monday)..date.end_of_week(:monday)
      used = self.class.where(user_id: user_id, decided_by_id: user_id, status: "approved", date: week).count
      HrLite.config.self_regularization[:per_week] - used
    end

    # --- transitions -------------------------------------------------------

    # Applies the proposed times to the day's record (creating it if the
    # person never punched at all). Only the provided times overwrite —
    # a forgot-checkout ticket keeps the genuine GPS check-in untouched.
    # A merge that would produce a nonsense record (checkout before the
    # existing check-in, or a checkout with no check-in at all) raises
    # InvalidMerge with the real story so the admin knows what to fix.
    def approve!(actor:, note: nil, notify: true)
      transition!("approved", actor, note) do
        # Re-checked at approval, not only at create: leave can be approved for
        # that day while the ticket waits in the queue, and DayStatus ranks
        # full-day leave above any punch — so the "fix" would write a record
        # nothing reads while telling everyone attendance had been corrected.
        if LeaveRequest.active_on(date).where(user_id: user_id, half_day: false).exists?
          raise InvalidMerge, "the day is now covered by approved leave — cancel the leave first"
        end

        record = AttendanceRecord.find_or_initialize_by(user_id: user_id, date: date)
        record.check_in_at = check_in_at if check_in_at
        record.check_out_at = check_out_at if check_out_at
        if record.check_in_at.nil?
          raise InvalidMerge, "the day has no check-in — the ticket needs a check-in time too"
        end

        # Lifts only the close job's half day; one HR set on purpose stays.
        record.status = "present" if record.status.blank? || AttendanceRecord::AUTO_NOTES.include?(record.regularization_note)
        record.regularized_by_id = actor.id
        record.regularized_at = Time.current
        record.regularization_note = "Ticket ##{id}: #{reason}"
        raise InvalidMerge, record.errors.full_messages.to_sentence unless record.valid?

        record.save!
        AuditLog.record!(
          action: "regularize", subject: record, actor: actor,
          changes: { "date" => record.date.to_s, "ticket" => id, "note" => reason }
        )
        # A slip computed before this fix still counts the old day; a recompute clears the note.
        run = PayrollRun.find_by(period_month: date.beginning_of_month, status: "review")
        run&.update!(warnings: run.warnings + [ "#{HrLite.display_name(user)}'s attendance on #{date.strftime('%d %b')} " \
                                               "was fixed after compute — recompute" ])
      end
      return true unless notify # self-fix: the flash and the audit row are the trail

      Notifications.publish(
        "regularization.approved",
        title: "Attendance fixed for #{date.strftime('%d %b')} (#{times_label})",
        body: decision_note.presence,
        path: "/regularization_requests",
        bell_to: [ user ], email_to: [ user ]
      )
      true
    end

    def reject!(actor:, note:)
      transition!("rejected", actor, note)
      Notifications.publish(
        "regularization.rejected",
        title: "Regularization rejected — #{date.strftime('%d %b')}",
        body: decision_note.presence,
        path: "/regularization_requests",
        bell_to: [ user ], email_to: [ user ]
      )
      true
    end

    def cancel!(actor:)
      transition!("cancelled", actor, nil)
      Notifications.publish(
        "regularization.cancelled",
        title: "#{HrLite.display_name(user)} cancelled a regularization ticket (#{date.strftime('%d %b')})",
        path: "/admin/regularization_requests",
        bell_to: HrLite.admin_users
      )
      true
    end

    # The merged attendance record would be invalid — surfaced to the
    # deciding admin verbatim; the ticket stays pending.
    class InvalidMerge < StandardError; end

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
      return unless date

      errors.add(:date, "cannot be in the future") if date > Date.current
    end

    def at_least_one_time
      return if check_in_at || check_out_at || short_day_ticket?

      errors.add(:base, "Propose a check-in time, a check-out time, or both")
    end

    def times_fall_on_date
      return unless date

      [ [ :check_in_at, check_in_at ], [ :check_out_at, check_out_at ] ].each do |attr, time|
        next unless time
        next if attr == :check_out_at && check_in_at && time.to_date == date + 1 && time < check_in_at + 1.day # night shift

        errors.add(attr, "must be on #{date.strftime('%d %b')}") unless time.to_date == date
      end
    end

    def checkout_after_checkin
      return unless check_in_at && check_out_at
      return if check_out_at > check_in_at

      errors.add(:check_out_at, "must be after check-in")
    end

    def no_duplicate_pending
      return unless date

      clash = self.class.pending.where(user_id: user_id, date: date).where.not(id: id)
      errors.add(:date, "already has a pending ticket") if clash.exists?
    end

    # A punch on a day covered by approved full-day leave would contradict
    # the leave (which wins in every display and still burns the balance).
    def no_approved_leave_conflict
      return unless date

      leave = LeaveRequest.active_on(date).where(user_id: user_id, half_day: false)
      errors.add(:date, "is covered by your approved leave — cancel the leave first") if leave.exists?
    end

    # A self-fix approve! can't merge (e.g. no check-in yet) -> an ordinary ticket.
    def self_fix_or_notify
      user.lock! if HrLite.config.self_regularization # one user's tickets at once can't both spend the last fix
      return approve!(actor: user, note: "Self-fixed", notify: false) if self_fixable?

      notify_requested
    rescue InvalidMerge
      notify_requested
    end

    def notify_requested
      Notifications.publish(
        "regularization.requested",
        title: "#{HrLite.display_name(user)} raised a regularization ticket for #{date.strftime('%d %b')} " \
               "(#{times_label})",
        body: reason.presence,
        path: "/admin/regularization_requests/#{id}",
        bell_to: HrLite.admin_users
      )
    end
  end
end
