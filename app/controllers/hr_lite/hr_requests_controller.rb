module HrLite
  # The employee's side of the help desk.
  class HrRequestsController < ApplicationController
    before_action :require_raising!

    def index
      @requests = paginate(own.recent_first)
    end

    def show
      @request = own.find(params[:id])
    end

    def new
      @request = HrRequest.new
    end

    def create
      @request = HrRequest.new(request_params.merge(user_id: hr_current_user.id))
      if @request.save
        redirect_to hr_requests_path, notice: "Sent to HR."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def cancel
      request = own.find(params[:id])
      request.cancel!(actor: hr_current_user)
      redirect_to hr_requests_path, notice: "Request withdrawn."
    rescue ActiveRecord::RecordInvalid
      redirect_to hr_requests_path, alert: "That request has already been answered."
    end

    private

    def require_raising! = hr_require_permission!("hr_request.raise")

    def own = HrRequest.where(user_id: hr_current_user.id)

    def request_params = params.require(:hr_request).permit(:category, :subject, :body)
  end
end
