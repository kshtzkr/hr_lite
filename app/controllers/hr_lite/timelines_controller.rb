module HrLite
  # Anyone's year on one page. Every employee may open a colleague's timeline;
  # HrLite::Timeline decides which events the viewer is allowed to see.
  class TimelinesController < ApplicationController
    def show
      @person = params[:user_id] ? HrLite.employees.find { |u| u.id == params[:user_id].to_i } : hr_current_user
      raise ActiveRecord::RecordNotFound unless @person

      year = params[:year].to_i
      @year = year.between?(2000, 2100) ? year : Date.current.year
      @profile = EmployeeProfile.find_by(user_id: @person.id)
      @events = Timeline.new(user: @person, viewer: hr_current_user, year: @year).events
    end
  end
end
