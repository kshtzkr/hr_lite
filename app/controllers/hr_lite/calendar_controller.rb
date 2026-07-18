module HrLite
  # Server-rendered company calendar: holidays, everyone's approved leaves
  # and weekend shading for a month. No JS dependency — works everywhere
  # the engine is mounted.
  class CalendarController < ApplicationController
    def show
      @month = parse_month_param(params[:month])
      range = @month.beginning_of_month..@month.end_of_month
      @calendar = WorkingCalendar.new(range)
      @holidays = Holiday.in_range(range).order(:date).group_by(&:date)
      @leaves = LeaveRequest.approved.includes(:leave_type, :user)
                            .overlapping_range(range.first, range.last)
                            .each_with_object(Hash.new { |h, k| h[k] = [] }) do |request, acc|
        (request.start_date..request.end_date).each do |date|
          acc[date] << request if range.cover?(date)
        end
      end
    end
  end
end
