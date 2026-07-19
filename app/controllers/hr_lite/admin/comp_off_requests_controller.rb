module HrLite
  module Admin
    class CompOffRequestsController < BaseController
      def index
        @status = params[:status].presence_in(CompOffRequest::STATUSES) || "pending"
        @requests = paginate(CompOffRequest.includes(:user).where(status: @status).recent_first)
      end

      def show
        @request = CompOffRequest.find(params[:id])
      end

      def approve
        request = CompOffRequest.find(params[:id])
        request.approve!(actor: hr_current_user, note: params[:decision_note].presence)
        redirect_to admin_comp_off_requests_path,
                    notice: "Approved — #{request.credit_days.to_f} day credited."
      rescue CompOffRequest::MissingCompOffType, CompOffRequest::StaleOffDay => e
        redirect_to admin_comp_off_request_path(request), alert: e.message
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_comp_off_request_path(request), alert: "Only pending requests can be decided."
      end

      def reject
        request = CompOffRequest.find(params[:id])
        note = params[:decision_note].to_s.strip
        if note.blank?
          return redirect_to admin_comp_off_request_path(request), alert: "A note is required to reject."
        end

        request.reject!(actor: hr_current_user, note: note)
        redirect_to admin_comp_off_requests_path, notice: "Request rejected."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_comp_off_request_path(request), alert: "Only pending requests can be decided."
      end
    end
  end
end
