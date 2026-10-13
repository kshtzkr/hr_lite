module HrLite
  # Employee-side WFH requests. Scoping to hr_current_user IS the
  # authorization; there is no edit, so a decided request cannot change.
  class WfhRequestsController < ApplicationController
    def index
      @requests = paginate(WfhRequest.where(user_id: hr_current_user.id).recent_first)
      @request = WfhRequest.new(start_date: Date.current, end_date: Date.current)
      load_calendar
    end

    def create
      @request = WfhRequest.new(params.require(:wfh_request).permit(:start_date, :end_date, :reason)
                                      .merge(user_id: hr_current_user.id, status: "pending"))
      # Row lock on the user: two tabs can't both pass the overlap check.
      saved = WfhRequest.transaction { HrLite.user_klass.lock.find(hr_current_user.id) && @request.save }
      if saved
        @request.notify_requested
        redirect_to wfh_requests_path, notice: "WFH request sent to HR."
      else
        @requests = paginate(WfhRequest.where(user_id: hr_current_user.id).recent_first)
        load_calendar
        render :index, status: :unprocessable_entity
      end
    end

    def cancel
      WfhRequest.where(user_id: hr_current_user.id).find(params[:id]).cancel!(actor: hr_current_user)
      redirect_to wfh_requests_path, notice: "WFH request cancelled."
    rescue ActiveRecord::RecordInvalid
      redirect_to wfh_requests_path, alert: "Only pending requests can be cancelled."
    end

    private

    # Status per date for the next 30 days; a later request wins a shared date.
    def load_calendar
      @window = Date.current..(Date.current + WfhRequest::MAX_DAYS_AHEAD)
      @day_status = {}
      WfhRequest.where(user_id: hr_current_user.id, status: %w[pending approved rejected])
                .overlapping(@window.first, @window.last).order(:id).each do |request|
        (request.start_date..request.end_date).each { |d| @day_status[d] = request.status if @window.cover?(d) }
      end
    end
  end
end
