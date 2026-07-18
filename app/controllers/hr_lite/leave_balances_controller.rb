module HrLite
  class LeaveBalancesController < ApplicationController
    def index
      year = params[:year].to_i
      @year = year.between?(2000, 2100) ? year : Date.current.year
      @balances = LeaveType.active.where(paid: true).where.not(annual_quota: nil).map do |type|
        LeaveBalance.for(hr_current_user, type, @year)
      end
    end
  end
end
