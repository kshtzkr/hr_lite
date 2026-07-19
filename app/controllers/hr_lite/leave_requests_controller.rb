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
      @request = LeaveRequest.new(start_date: Date.current, end_date: Date.current)
      @balances = balance_cards
    end

    def create
      @request = LeaveRequest.new(request_params.merge(user_id: hr_current_user.id))
      if @request.save
        redirect_to leave_requests_path, notice: "Leave request submitted."
      else
        @balances = balance_cards
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
      year = Date.current.year
      LeaveType.active.where(paid: true).where.not(annual_quota: nil).map do |type|
        LeaveBalance.for(hr_current_user, type, year)
      end
    end

    def request_params
      params.require(:leave_request).permit(:leave_type_id, :start_date, :end_date, :half_day, :reason)
    end
  end
end
