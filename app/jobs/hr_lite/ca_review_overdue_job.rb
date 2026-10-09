module HrLite
  # Schedule on 31 March evening: anything the CA has not verified, or a flag
  # nobody resolved, goes to payroll and HR as overdue.
  class CaReviewOverdueJob < ApplicationJob
    queue_as :default

    def perform(on: Date.current)
      left = CaReview.outstanding(FinancialYear.start_for(on))
      return if left.values.sum.zero?

      people = HrLite.users_holding("payroll.approve", scope: :all).to_a | HrLite.users_holding("payroll.manage", scope: :all).to_a
      Notifications.publish(
        "ca.overdue",
        title: "CA review overdue: #{left['slips']} slips, #{left['declarations']} declarations unverified, #{left['flagged']} flags open",
        path: "/admin/ca_reviews?status=unreviewed", bell_to: people, email_to: people
      )
    end
  end
end
