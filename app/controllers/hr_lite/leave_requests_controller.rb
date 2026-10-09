module HrLite
  # Employee self-service: always scoped to hr_current_user — a foreign id
  # 404s, never 403s.
  class LeaveRequestsController < ApplicationController
    def index
      @requests = paginate(own_requests.recent_first.includes(:leave_type))
      @balances = balance_cards
    end

    def show
      @request = own_requests.find(params[:id])
    end

    def new
      @request = LeaveRequest.new(start_date: (parse_date_param(params[:date]) if params[:date].present?),
                                  leave_type_id: params[:leave_type_id])
      @balances = balance_cards
      @out_soon = colleagues_out_soon
    end

    def create
      @request = LeaveRequest.new(request_params.merge(user_id: hr_current_user.id))
      @request.end_date ||= @request.start_date # a blank "To" means one day
      if @request.save
        # Say it now, not on the payslip: days past the balance are unpaid.
        short = @request.days_beyond_balance
        redirect_to leave_requests_path, notice: "Leave request submitted.#{" #{helpers.hrl_days(short)} day(s) are beyond your balance and will be unpaid if approved." if short.positive?}"
      else
        @balances = balance_cards
        @out_soon = colleagues_out_soon
        render :new, status: :unprocessable_entity
      end
    end

    def cancel
      request = own_requests.find(params[:id])
      if request.cancellable_by?(hr_current_user)
        request.cancel!(actor: hr_current_user)
        redirect_to leave_requests_path, notice: "Leave cancelled."
      else
        redirect_to leave_requests_path, alert: "This request can no longer be cancelled."
      end
    end

    private

    def own_requests
      LeaveRequest.where(user_id: hr_current_user.id)
    end

    def balance_cards
      year = LeaveYear.current_key
      LeaveType.active.where(paid: true).where.not(annual_quota: nil).map do |type|
        LeaveBalance.for(hr_current_user, type, year)
      end
    end

    # Approved leave only, name and dates; the type stays private (see _out_list).
    def colleagues_out_soon
      LeaveRequest.approved.overlapping_range(Date.current, Date.current + 14)
                  .where(user_id: HrLite.active_employees.map(&:id)).where.not(user_id: hr_current_user.id)
                  .includes(:user).order(:start_date, :id).to_a
    end

    def request_params
      params.require(:leave_request).permit(:leave_type_id, :start_date, :end_date, :half_day, :half_day_part, :reason)
    end
  end
end
