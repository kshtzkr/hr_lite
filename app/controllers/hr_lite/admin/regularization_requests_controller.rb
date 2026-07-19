module HrLite
  module Admin
    class RegularizationRequestsController < BaseController
      def index
        @status = params[:status].presence_in(RegularizationRequest::STATUSES) || "pending"
        @requests = paginate(RegularizationRequest.includes(:user).where(status: @status).recent_first)
      end

      def show
        @request = RegularizationRequest.find(params[:id])
      end

      def approve
        request = RegularizationRequest.find(params[:id])
        request.approve!(actor: hr_current_user, note: params[:decision_note].presence)
        redirect_to admin_regularization_requests_path, notice: "Ticket approved — attendance fixed."
      rescue RegularizationRequest::InvalidMerge => e
        redirect_to admin_regularization_request_path(request),
                    alert: "Cannot apply — #{e.message}. Fix the day manually or reject with a note."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_regularization_request_path(request), alert: "Only pending tickets can be decided."
      end

      def reject
        request = RegularizationRequest.find(params[:id])
        note = params[:decision_note].to_s.strip
        if note.blank?
          return redirect_to admin_regularization_request_path(request), alert: "A note is required to reject."
        end

        request.reject!(actor: hr_current_user, note: note)
        redirect_to admin_regularization_requests_path, notice: "Ticket rejected."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_regularization_request_path(request), alert: "Only pending tickets can be decided."
      end
    end
  end
end
