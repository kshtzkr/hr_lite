module HrLite
  # Central event bus. Domain code publishes an event; the per-event channel
  # row (host-overridable via config.notification_matrix) decides which
  # channels fire. Channel semantics:
  #
  #   bell:             in-app notification (config.notify) to `bell_to` users
  #   email:            EventMailer to each `email_to` user
  #   leadership_email: ONE email to every configured leadership address
  #   leadership_bell:  in-app notification to each leadership user record
  #
  # Recipients are computed by the publishing site (it knows the domain);
  # the matrix is purely the on/off routing table.
  module Notifications
    DEFAULT_MATRIX = {
      "leave.requested"       => { bell: true,  email: false, leadership_email: true,  leadership_bell: true  },
      "leave.approved"        => { bell: true,  email: true,  leadership_email: true,  leadership_bell: false },
      "leave.rejected"        => { bell: true,  email: true,  leadership_email: true,  leadership_bell: false },
      "leave.cancelled"       => { bell: true,  email: false, leadership_email: true,  leadership_bell: false },
      "attendance.flagged"    => { bell: true,  email: false, leadership_email: false, leadership_bell: false },
      "attendance.regularized" => { bell: true, email: true,  leadership_email: true,  leadership_bell: false },
      "payroll.finalized"     => { bell: false, email: false, leadership_email: true,  leadership_bell: true  },
      "payroll.published"     => { bell: true,  email: true,  leadership_email: true,  leadership_bell: false },
      "kudos.mentioned"       => { bell: true,  email: true,  leadership_email: false, leadership_bell: false },
      "appraisal.shared"      => { bell: true,  email: true,  leadership_email: true,  leadership_bell: false },
      "promotion.recorded"    => { bell: true,  email: true,  leadership_email: true,  leadership_bell: true  },
      "policy.changed"        => { bell: false, email: false, leadership_email: true,  leadership_bell: true  },
      "digest.daily"          => { bell: false, email: false, leadership_email: true,  leadership_bell: false },
      "resignation.submitted" => { bell: true,  email: false, leadership_email: true,  leadership_bell: true  },
      "resignation.accepted"  => { bell: true,  email: true,  leadership_email: true,  leadership_bell: false },
      "resignation.withdrawn" => { bell: true,  email: false, leadership_email: true,  leadership_bell: false },
      "employee.onboarded"    => { bell: true,  email: true,  leadership_email: true,  leadership_bell: false },
      "payroll.draft_ready"   => { bell: false, email: false, leadership_email: true,  leadership_bell: true  },
      "leave.team_notice"     => { bell: true,  email: true,  leadership_email: false, leadership_bell: false },
      "comp_off.requested"    => { bell: true,  email: false, leadership_email: true,  leadership_bell: true  },
      "comp_off.approved"     => { bell: true,  email: true,  leadership_email: true,  leadership_bell: false },
      "comp_off.rejected"     => { bell: true,  email: true,  leadership_email: false, leadership_bell: false },
      "comp_off.cancelled"    => { bell: true,  email: false, leadership_email: true,  leadership_bell: false },
      "regularization.requested" => { bell: true, email: false, leadership_email: true,  leadership_bell: false },
      "regularization.approved"  => { bell: true, email: true,  leadership_email: true,  leadership_bell: false },
      "regularization.rejected"  => { bell: true, email: true,  leadership_email: false, leadership_bell: false },
      "regularization.cancelled" => { bell: true, email: false, leadership_email: true,  leadership_bell: false }
    }.freeze

    class << self
      # DEFAULT under the host override: a host matrix pinned on an older
      # gem version keeps working when new events ship (rows it doesn't
      # know about fall back to the defaults instead of vanishing).
      def matrix
        DEFAULT_MATRIX.merge(HrLite.config.notification_matrix || {})
      end

      def publish(event, title:, body: nil, path: nil, bell_to: [], email_to: [], lines: [], diff: nil, link_url: nil)
        row = matrix[event.to_s]
        unless row
          Rails.logger.warn("[hr_lite] unknown notification event #{event}")
          return
        end

        deliver_bells(event, row, bell_to, title, body, path)
        deliver_emails(row, email_to, title, body, path, lines, link_url)
        deliver_leadership_email(event, row, title, body, path, lines, diff)
        deliver_leadership_bells(event, row, bell_to, title, body, path)
        nil
      end

      private

      def deliver_bells(event, row, bell_to, title, body, path)
        return unless row[:bell]

        Array(bell_to).compact.uniq.each do |user|
          HrLite.notify(user: user, kind: event.to_s, title: title, body: body, path: path)
        end
      end

      def deliver_emails(row, email_to, title, body, path, lines, link_url = nil)
        return unless row[:email]

        Array(email_to).compact.uniq.each do |user|
          next if user.email.blank?

          EventMailer.event(to: user.email, subject: title, heading: title,
                            body: body, lines: lines, path: path,
                            link_url: link_url).deliver_later
        end
      rescue => e
        Rails.logger.error("[hr_lite] event email failed: #{e.class}: #{e.message}")
      end

      def deliver_leadership_email(event, row, title, body, path, lines, diff)
        return unless row[:leadership_email]

        recipients = HrLite.config.leadership_emails.map { |e| e.to_s.strip }.reject(&:empty?)
        return if recipients.empty?

        EventMailer.leadership(to: recipients, subject: "[HR] #{title}", heading: title,
                               body: body, lines: lines, diff: diff, path: path, event: event.to_s)
                   .deliver_later
      rescue => e
        Rails.logger.error("[hr_lite] leadership email failed: #{e.class}: #{e.message}")
      end

      def deliver_leadership_bells(event, row, bell_to, title, body, path)
        return unless row[:leadership_bell]

        already = Array(bell_to).compact
        HrLite.leadership_users.each do |leader|
          next if already.any? { |u| u.id == leader.id }

          HrLite.notify(user: leader, kind: event.to_s, title: title, body: body, path: path)
        end
      rescue => e
        Rails.logger.error("[hr_lite] leadership bell failed: #{e.class}: #{e.message}")
      end
    end
  end
end
