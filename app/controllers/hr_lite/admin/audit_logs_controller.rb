module HrLite
  module Admin
    class AuditLogsController < LeadershipController
      def index
        # Appraisal and promotion rows carry review text in plain columns:
        # ordinary leadership governs people and policy, not pay.
        scope = hr_superadmin? ? AuditLog.recent : AuditLog.recent.outside_money_tier
        @audit_logs = paginate(scope.includes(:actor))
      end
    end
  end
end
