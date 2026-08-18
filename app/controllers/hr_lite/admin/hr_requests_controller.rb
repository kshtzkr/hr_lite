module HrLite
  module Admin
    # The desk itself.
    class HrRequestsController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_desk!

      def index
        @status = params[:status].presence_in(HrRequest::STATUSES) || "open"
        @requests = paginate(HrRequest.where(status: @status).includes(:user, :assigned_to)
                                      .recent_first)
      end

      def show
        @request = HrRequest.find(params[:id])
      end

      def assign
        request = HrRequest.find(params[:id])
        assignee = HrLite.user_klass.find(params[:assignee_id])
        request.assign!(actor: hr_current_user, assignee: assignee)
        redirect_to admin_hr_request_path(request), notice: "Assigned to #{HrLite.display_name(assignee)}."
      end

      def resolve
        request = HrRequest.find(params[:id])
        request.resolve!(actor: hr_current_user, resolution: params[:resolution].to_s.strip)
        redirect_to admin_hr_requests_path, notice: "Answered."
      rescue ArgumentError
        redirect_to admin_hr_request_path(request), alert: "Write an answer before resolving."
      end

      private

      def require_desk! = hr_require_permission!("hr_request.manage", scope: :all)
    end
  end
end
