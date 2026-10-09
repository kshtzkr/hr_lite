module HrLite
  # Monthly automation: on the 1st, draft + compute the previous month's
  # payroll from attendance and the policy, then tell whoever runs payroll
  # (payroll.manage) it is waiting for review — leadership cannot open it. Publishing stays a deliberate human action —
  # the system prepares, people approve.
  class PayrollAutoDraftJob < ApplicationJob
    queue_as :default

    def perform(month: Date.current.prev_month.beginning_of_month)
      return unless EmployeeProfile.active_for(month).exists?

      run = PayrollRun.find_or_create_by!(period_month: month)
      # Only ever drafts an UNTOUCHED run. Accepting `review` as well meant a
      # re-run recomputed a month somebody was already reviewing and told
      # leadership all over again that it was waiting for them.
      return unless run.draft? && run.salary_slips.none?

      run.compute!(actor: nil)
      payroll = HrLite.users_holding("payroll.approve", scope: :all).to_a | HrLite.users_holding("payroll.manage", scope: :all).to_a
      Notifications.publish(
        "payroll.draft_ready",
        title: "Payroll #{run.label} computed from attendance — #{run.salary_slips.count} slips await review",
        path: "/admin/payroll_runs/#{run.id}", bell_to: payroll, email_to: payroll
      )
    end
  end
end
