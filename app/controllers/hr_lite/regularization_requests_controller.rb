module HrLite
  # Employee-side regularization tickets: propose punch times for a day you
  # forgot to check in/out. Scoping to hr_current_user IS the authorization.
  class RegularizationRequestsController < ApplicationController
    def index
      @requests = paginate(RegularizationRequest.where(user_id: hr_current_user.id).recent_first)
    end

    def new
      @request = RegularizationRequest.new(date: parse_date_param(params[:date]))
    end

    def create
      @request = RegularizationRequest.new(request_params.merge(user_id: hr_current_user.id))
      if @request.save
        redirect_to regularization_requests_path, notice: create_notice
      else
        render :new, status: :unprocessable_entity
      end
    end

    def cancel
      request = RegularizationRequest.where(user_id: hr_current_user.id).find(params[:id])
      request.cancel!(actor: hr_current_user)
      redirect_to regularization_requests_path, notice: "Ticket cancelled."
    rescue ActiveRecord::RecordInvalid
      redirect_to regularization_requests_path, alert: "Only pending tickets can be cancelled."
    end

    private

    def create_notice
      rule = HrLite.config.self_regularization
      return "Ticket raised — an admin will review it." unless rule
      return "Fixed. #{helpers.pluralize(@request.self_fixes_left, 'self-fix')} left this week." if @request.approved?

      "Sent to HR as a ticket — you can fix only a missed punch on a working day in the last #{rule[:within_days]} days yourself, " \
        "#{rule[:per_week]} times a week."
    end

    def request_params
      params.require(:regularization_request).permit(:date, :check_in_at, :check_out_at, :reason)
    end
  end
end
