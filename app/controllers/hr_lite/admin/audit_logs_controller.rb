module HrLite
  module Admin
    class AuditLogsController < LeadershipController
      def index
        @audit_logs = paginate(AuditLog.recent.includes(:actor))
      end
    end
  end
end
