module HrLite
  class HolidaysController < ApplicationController
    def index
      year = params[:year].to_i
      @year = year.between?(2000, 2100) ? year : Date.current.year
      office = WorkingCalendar.office_for(hr_current_user.id) # yours plus the all-office ones
      @holidays = Holiday.for_office(office).where(date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).order(:date)
      @next_holiday_id = Holiday.company_wide.for_office(office).upcoming.pick(:id)
    end
  end
end
