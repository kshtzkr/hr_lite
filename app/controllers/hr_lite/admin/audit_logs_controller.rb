module HrLite
  module Admin
    class AuditLogsController < LeadershipController
      skip_before_action :require_governing_access!
      before_action -> { hr_require_permission!("audit.view", scope: :all) }

      def index
        # Appraisal and promotion rows carry review text in plain columns:
        # ordinary leadership governs people and policy, not pay.
        scope = hr_can?("audit.view_money", scope: :all) ? AuditLog.recent : AuditLog.recent.outside_money_tier
        scope = scope.where.not("action LIKE ?", "%.viewed") unless params[:views] # page views drown the changes
        @audit_logs = paginate(scope.includes(:actor))
      end
    end
  end
end
