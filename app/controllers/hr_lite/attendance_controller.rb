module HrLite
  # Employee self-service punch surface. Always operates on hr_current_user —
  # there is no user param, so punching for someone else is structurally
  # impossible.
  class AttendanceController < ApplicationController
    def show
      @month = parse_month_param(params[:month])
      @record = AttendanceRecord.find_by(user_id: hr_current_user.id, date: Date.current)
      @day_status = DayStatus.new(user: hr_current_user, range: @month.beginning_of_month..@month.end_of_month)
      @counts = @day_status.counts
      @counts[:absent] -= 1 if @month.all_month.cover?(Date.current) && @day_status.for(Date.current).kind == :absent
      # ?day= opens the day detail; garbage (parsed as today), other months and the future open nothing.
      day = parse_date_param(params[:day])
      @day = day if params[:day] == day.iso8601 && @month.all_month.cover?(day) && day <= Date.current
      @day_info = @day_status.for(@day) if @day
      @day_ticket = RegularizationRequest.where(user_id: hr_current_user.id, date: @day).recent_first.first if @day
    end

    def check_in
      punch(:check_in)
    end

    def check_out
      punch(:check_out)
    end

    private

    def punch(kind)
      result = AttendancePuncher.call(user: hr_current_user, kind: kind, **punch_params.to_h.symbolize_keys)
      if result.ok?
        time = Time.current.strftime("%H:%M")
        redirect_to attendance_path, notice: "#{kind == :check_in ? 'Checked in' : 'Checked out'} at #{time}."
      else
        redirect_to attendance_path, alert: result.error
      end
    end

    def punch_params
      params.permit(:lat, :lng, :accuracy_m, :geo_status)
    end
  end
end
