module HrLite
  module Admin
    class CompOffRequestsController < BaseController
      def index
        @status = params[:status].presence_in(CompOffRequest::STATUSES) || "pending"
        @requests = paginate(hr_scope(CompOffRequest.includes(:user).where(status: @status).recent_first,
                                      "leave.view"))
      end

      def show
        @request = find_decidable
      end

      def approve
        request = find_decidable
        request.approve!(actor: hr_current_user, note: params[:decision_note].presence)
        redirect_to admin_comp_off_requests_path,
                    notice: "Approved — #{request.credit_days.to_f} day credited."
      rescue CompOffRequest::MissingCompOffType, CompOffRequest::StaleOffDay => e
        redirect_to admin_comp_off_request_path(request), alert: e.message
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_comp_off_request_path(request), alert: "Only pending requests can be decided."
      end

      def reject
        request = find_decidable
        note = params[:decision_note].to_s.strip
        if note.blank?
          return redirect_to admin_comp_off_request_path(request), alert: "A note is required to reject."
        end

        request.reject!(actor: hr_current_user, note: note)
        redirect_to admin_comp_off_requests_path, notice: "Request rejected."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_comp_off_request_path(request), alert: "Only pending requests can be decided."
      end

      private

      # A manager decides for their own reports; HR decides for everyone.
      # Scoped through the relation, so reaching for somebody else's report
      # is a 404 rather than a 403 that confirms the person exists.
      def decidable
        hr_scope(CompOffRequest.all, "leave.approve")
      end

      def find_decidable = decidable.find(params[:id])
    end
  end
end
