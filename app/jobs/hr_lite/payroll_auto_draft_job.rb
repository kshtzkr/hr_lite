module HrLite
  # Monthly automation: on the 1st, draft + compute the previous month's
  # payroll from attendance and the policy, then tell leadership it is
  # waiting for review. Publishing stays a deliberate human action —
  # the system prepares, people approve.
  class PayrollAutoDraftJob < ActiveJob::Base
    queue_as :default

    def perform(month: Date.current.prev_month.beginning_of_month)
      return unless EmployeeProfile.active_for(month).exists?

      run = PayrollRun.find_or_create_by!(period_month: month)
      return unless run.draft? || run.review?

      run.compute!(actor: nil)
      Notifications.publish(
        "payroll.draft_ready",
        title: "Payroll #{run.label} computed from attendance — #{run.salary_slips.count} slips await review",
        path: "/admin/payroll_runs/#{run.id}"
      )
    end
  end
end
