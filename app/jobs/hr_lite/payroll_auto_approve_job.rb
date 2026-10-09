module HrLite
  # The 3rd-of-month backstop (schedule it on the 3rd): last month's run that
  # is still in review is approved and published by the system, unless it has
  # blocking warnings — then the approvers are told it is overdue instead.
  class PayrollAutoApproveJob < ApplicationJob
    queue_as :default

    def perform(month: Date.current.prev_month.beginning_of_month)
      run = PayrollRun.find_by(period_month: month, status: "review")
      return unless run
      return if run.auto_approve!

      people = HrLite.users_holding("payroll.approve", scope: :all).to_a
      Notifications.publish(
        "payroll.overdue",
        title: "Payroll #{run.label} is overdue — not auto-approved: #{run.blocking_warnings.join('; ')}",
        path: "/admin/payroll_runs/#{run.id}", bell_to: people, email_to: people
      )
    end
  end
end
