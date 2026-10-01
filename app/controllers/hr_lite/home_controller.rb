module HrLite
  class HomeController < ApplicationController
    def index
      @latest_kudos = Kudo.recent.includes(:giver, kudo_mentions: :user).limit(3)
      @out_today = LeaveRequest.active_on(Date.current).includes(:user)
                               .where(user_id: HrLite.active_employees.map(&:id))
                               .sort_by { |leave| hr_display_name(leave.user).downcase }
    end
  end
end
