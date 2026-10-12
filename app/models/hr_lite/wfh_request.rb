module HrLite
  # "Let me work from home on these dates." HR approves or rejects; only an
  # approved request covering today lets a check-in skip the office geofence.
  class WfhRequest < ApplicationRecord
    STATUSES = %w[pending approved rejected cancelled].freeze
    MAX_DAYS_AHEAD = 30

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :decided_by, class_name: HrLite.config.user_class, optional: true

    validates :start_date, :end_date, :reason, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :dates_in_window, :no_overlap, on: :create

    scope :pending, -> { where(status: "pending") }
    scope :approved, -> { where(status: "approved") }
    scope :live, -> { where(status: %w[pending approved]) }
    scope :overlapping, ->(from, to) { where("start_date <= ? AND end_date >= ?", to, from) }
    scope :recent_first, -> { order(start_date: :desc, id: :desc) }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    def self.approved_for(user_id, date) = approved.where(user_id: user_id).overlapping(date, date).first

    def dates_label
      start_date == end_date ? start_date.strftime("%a %-d %b") : "#{start_date.strftime('%-d %b')} – #{end_date.strftime('%-d %b')}"
    end

    def days = (end_date - start_date).to_i + 1

    def approve!(actor:, note: nil)
      transition!("approved", actor, note)
      announce("wfh.approved", "WFH approved — #{dates_label}", decision_note, "/wfh_requests", [ user ])
    end

    def reject!(actor:, note:)
      transition!("rejected", actor, note)
      announce("wfh.rejected", "WFH rejected — #{dates_label}", decision_note, "/wfh_requests", [ user ])
    end

    def cancel!(actor:)
      transition!("cancelled", actor, nil)
      announce("wfh.cancelled", "#{HrLite.display_name(user)} cancelled WFH for #{dates_label}", nil,
               "/admin/wfh_requests/#{id}", HrLite.admin_users)
    end

    def notify_requested
      AuditLog.record!(action: "wfh.requested", subject: self, actor: user,
                       changes: { "dates" => dates_label, "reason" => reason })
      announce("wfh.requested", "#{HrLite.display_name(user)} requested WFH for #{dates_label}", reason,
               "/admin/wfh_requests/#{id}", HrLite.admin_users)
    end

    private

    def transition!(new_status, actor, note)
      with_lock do
        raise ActiveRecord::RecordInvalid.new(self), "not pending" unless pending?

        update!(status: new_status, decided_by_id: actor.id, decided_at: Time.current, decision_note: note)
      end
      AuditLog.record!(action: "wfh.#{new_status}", subject: self, actor: actor,
                       changes: { "dates" => dates_label, "note" => note }.compact)
      true
    end

    # A notification failure never undoes a request or a decision.
    def announce(event, title, body, path, to)
      Notifications.publish(event, title: title, body: body.presence, path: path, bell_to: to,
                                   email_to: event == "wfh.requested" ? [] : to)
    rescue => e
      Rails.logger.error("[hr_lite] wfh notification failed: #{e.class}: #{e.message}")
    end

    def dates_in_window
      return unless start_date && end_date

      errors.add(:start_date, "cannot be in the past") if start_date < Date.current
      errors.add(:end_date, "must be on or after the start date") if end_date < start_date
      errors.add(:end_date, "must be within #{MAX_DAYS_AHEAD} days from today") if end_date > Date.current + MAX_DAYS_AHEAD
    end

    def no_overlap
      return unless start_date && end_date && user_id

      clash = self.class.live.where(user_id: user_id).overlapping(start_date, end_date).exists?
      errors.add(:base, "You already have a pending or approved WFH request on some of these dates") if clash
    end
  end
end
