module HrLite
  module Admin
    class OverviewController < BaseController
      SECTION_CAP = 10

      def index
        @query = OverviewQuery.new(user_ids: hr_access.visible_user_ids("leave.view"))
        @kpis = @query.kpis
        # Emails, bells and audit rows that failed in the background; the audit trail's own gate.
        return unless hr_can?("profile.manage", scope: :all)

        failures = AuditLog.recent.where("action LIKE ?", "failure.%").includes(:subject).limit(SECTION_CAP)
        @failures = hr_superadmin? ? failures : failures.outside_money_tier
      end
    end
  end
end
