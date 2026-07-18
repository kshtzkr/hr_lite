module HrLite
  module Admin
    class LeaveRequestsController < BaseController
      def index
        scope = LeaveRequest.includes(:leave_type, :user).recent_first
        @status = params[:status].presence_in(LeaveRequest::STATUSES) || "pending"
        @requests = paginate(scope.where(status: @status))
      end

      def show
        @request = LeaveRequest.includes(:leave_type).find(params[:id])
        @balance = @request.balance
      end

      def approve
        request = LeaveRequest.find(params[:id])
        if request.approve!(actor: hr_current_user, note: params[:decision_note].presence)
          redirect_to admin_leave_requests_path, notice: "Leave approved."
        else
          redirect_to admin_leave_request_path(request),
                      alert: "Cannot approve — balance no longer covers this request."
        end
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_leave_request_path(request), alert: "Only pending requests can be decided."
      end

      def reject
        request = LeaveRequest.find(params[:id])
        note = params[:decision_note].to_s.strip
        if note.blank?
          return redirect_to admin_leave_request_path(request), alert: "A note is required to reject."
        end

        request.reject!(actor: hr_current_user, note: note)
        redirect_to admin_leave_requests_path, notice: "Leave rejected."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_leave_request_path(request), alert: "Only pending requests can be decided."
      end
    end
  end
end
