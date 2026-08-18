module HrLite
  # Nudges approvals that have sat past their step's SLA. Escalation here
  # means TELLING SOMEBODY, not reassigning: silently moving a decision to
  # another person is how an approval ends up made by somebody who never saw
  # the request.
  #
  # Each row is stamped once, so a daily run does not re-nag every day.
  class ApprovalEscalationJob < ApplicationJob
    def perform(now: Time.current)
      overdue = Approval.pending.where(escalated_at: nil).includes(:step, :approver)
                        .select { |approval| approval.overdue?(now) }
      return if overdue.empty?

      overdue.group_by(&:approver_id).each do |approver_id, rows|
        approver = rows.first.approver
        next if approver.nil?

        Notifications.publish(
          "approval.escalated",
          title: "#{rows.size} approval#{'s' unless rows.size == 1} waiting on you past its deadline",
          lines: rows.map { |row| "#{row.label} — waiting #{waited(row, now)}" },
          path: "/approvals",
          bell_to: [ approver ],
          email_to: [ approver ],
          leadership: { title: "#{HrLite.display_name(approver)} has #{rows.size} overdue approval#{'s' unless rows.size == 1}" }
        )
      end

      Approval.where(id: overdue.map(&:id)).update_all(escalated_at: now) # rubocop:disable Rails/SkipsModelValidations
    end

    private

    def waited(approval, now)
      hours = ((now - approval.created_at) / 1.hour).floor
      hours < 48 ? "#{hours}h" : "#{(hours / 24)} days"
    end
  end
end
