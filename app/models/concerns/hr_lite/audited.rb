module HrLite
  # Include in every leadership-mutable model. Each create/update/destroy
  # writes an append-only AuditLog row and publishes policy.changed to
  # leadership. Encrypted attributes are logged as "[changed]" — plaintext
  # PII never reaches the audit table or email.
  module Audited
    extend ActiveSupport::Concern

    SKIPPED_ATTRIBUTES = %w[updated_at created_at].freeze
    REDACTED = "[changed]".freeze

    included do
      after_create  { hr_lite_audit!("create") }
      after_update  { hr_lite_audit!("update") }
      after_destroy { hr_lite_audit!("destroy") }
    end

    private

    def hr_lite_audit!(action)
      changes = hr_lite_audited_changes(action)
      return if action == "update" && changes.empty?

      log = HrLite::AuditLog.create!(
        actor: HrLite::Current.actor,
        action: action,
        subject_type: self.class.name,
        subject_id: id,
        audited_changes: changes
      )
      hr_lite_publish_policy_change(log)
    rescue => e
      # The trail is best-effort by design: an audit hiccup must never roll
      # back the domain write it describes. Logged loudly instead.
      Rails.logger.error("[hr_lite] audit failed: #{e.class}: #{e.message}")
    end

    def hr_lite_audited_changes(action)
      encrypted = self.class.try(:encrypted_attributes)&.map(&:to_s) || []

      case action
      when "destroy"
        { "_destroyed" => hr_lite_audit_label }
      else
        saved_changes.except(*SKIPPED_ATTRIBUTES).to_h do |attr, (from, to)|
          if encrypted.include?(attr)
            [ attr, REDACTED ]
          else
            [ attr, [ from, to ] ]
          end
        end
      end
    end

    def hr_lite_audit_label
      try(:name) || try(:title) || "#{self.class.name.demodulize} ##{id}"
    end

    def hr_lite_publish_policy_change(log)
      actor_name = HrLite.display_name(HrLite::Current.actor)
      subject = "#{self.class.name.demodulize.underscore.humanize} — #{hr_lite_audit_label}"
      HrLite::Notifications.publish(
        "policy.changed",
        title: "#{actor_name.presence || 'Someone'} #{log.action}d #{subject}",
        body: nil,
        diff: log.audited_changes
      )
    end
  end
end
