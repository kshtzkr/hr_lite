module HrLite
  # Employee-side comp-off: request a credit for working a weekend/holiday.
  # Scoping to hr_current_user IS the authorization.
  class CompOffRequestsController < ApplicationController
    def index
      @requests = paginate(CompOffRequest.where(user_id: hr_current_user.id).recent_first)
      @comp_off_type = LeaveType.comp_off_type
    end

    def new
      @request = CompOffRequest.new(date_worked: default_date)
    end

    def create
      @request = CompOffRequest.new(request_params.merge(user_id: hr_current_user.id))
      if @request.save
        redirect_to comp_off_requests_path, notice: "Comp-off request sent for approval."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def cancel
      request = CompOffRequest.where(user_id: hr_current_user.id).find(params[:id])
      request.cancel!(actor: hr_current_user)
      redirect_to comp_off_requests_path, notice: "Request cancelled."
    rescue ActiveRecord::RecordInvalid
      redirect_to comp_off_requests_path, alert: "Only pending requests can be cancelled."
    end

    private

    def request_params
      params.require(:comp_off_request).permit(:date_worked, :half_day, :reason)
    end

    # Most recent non-working day — the day they most likely worked extra.
    def default_date
      calendar = WorkingCalendar.new((Date.current - 14)..Date.current)
      (0..14).map { |i| Date.current - i }.find { |d| !calendar.working_day?(d) } || Date.current
    end
  end
end
