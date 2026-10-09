module HrLite
  # Schedule weekly in March: tells the CA reviewers what is left before 31 March.
  class CaReviewReminderJob < ApplicationJob
    queue_as :default

    def perform(on: Date.current)
      return unless on.month == 3

      left = CaReview.outstanding(FinancialYear.start_for(on))
      return if left.values.sum.zero?

      reviewers = HrLite.users_holding("payroll.verify", scope: :all).to_a
      Notifications.publish(
        "ca.reminder",
        title: "CA review: #{left['slips']} slips and #{left['declarations']} declarations left before 31 March" \
               "#{", #{left['flagged']} flagged" if left['flagged'].positive?}",
        path: "/admin/ca_reviews", bell_to: reviewers, email_to: reviewers
      )
    end
  end
end
