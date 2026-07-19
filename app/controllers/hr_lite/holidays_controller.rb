module HrLite
  class HolidaysController < ApplicationController
    def index
      year = params[:year].to_i
      @year = year.between?(2000, 2100) ? year : Date.current.year
      @holidays = Holiday.where(date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).order(:date)
    end
  end
end
