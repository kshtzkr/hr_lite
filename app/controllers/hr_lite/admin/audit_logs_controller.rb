module HrLite
  module Admin
    class AuditLogsController < LeadershipController
      def index
        # Appraisal and promotion rows carry review text in plain columns:
        # ordinary leadership governs people and policy, not pay.
        scope = hr_superadmin? ? AuditLog.recent : AuditLog.recent.outside_money_tier
        scope = scope.where.not("action LIKE ?", "%.viewed") unless params[:views] # page views drown the changes
        @audit_logs = paginate(scope.includes(:actor))
      end
    end
  end
end
