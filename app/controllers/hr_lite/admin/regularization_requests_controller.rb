module HrLite
  module Admin
    class RegularizationRequestsController < BaseController
      def index
        @status = params[:status].presence_in(RegularizationRequest::STATUSES) || "pending"
        @requests = paginate(hr_scope(RegularizationRequest.includes(:user).where(status: @status).recent_first,
                                      "attendance.view"))
      end

      def show
        @request = find_decidable
      end

      def approve
        request = find_decidable
        request.approve!(actor: hr_current_user, note: params[:decision_note].presence)
        redirect_to admin_regularization_requests_path, notice: "Ticket approved — attendance fixed."
      rescue RegularizationRequest::InvalidMerge => e
        redirect_to admin_regularization_request_path(request),
                    alert: "Cannot apply — #{e.message}. Fix the day manually or reject with a note."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_regularization_request_path(request), alert: "Only pending tickets can be decided."
      end

      def reject
        request = find_decidable
        note = params[:decision_note].to_s.strip
        if note.blank?
          return redirect_to admin_regularization_request_path(request), alert: "A note is required to reject."
        end

        request.reject!(actor: hr_current_user, note: note)
        redirect_to admin_regularization_requests_path, notice: "Ticket rejected."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_regularization_request_path(request), alert: "Only pending tickets can be decided."
      end

      private

      # A manager decides for their own reports; HR decides for everyone.
      # Scoped through the relation, so reaching for somebody else's report
      # is a 404 rather than a 403 that confirms the person exists.
      def decidable
        hr_scope(RegularizationRequest.all, "attendance.manage")
      end

      def find_decidable = decidable.find(params[:id])
    end
  end
end
