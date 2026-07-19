module HrLite
  # The everyone-visible team board: who's in, who's out, who's on leave,
  # hours worked — for any date. Transparency by design; shows punch times
  # and leave types only, never reasons or personal data.
  class TeamController < ApplicationController
    def show
      @date = parse_date_param(params[:date])
      @board = TeamDay.new(date: @date)
    end
  end
end
