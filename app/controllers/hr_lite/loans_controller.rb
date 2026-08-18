module HrLite
  # What an employee owes and what is coming out of the next payslip. Read
  # only: a loan is agreed with the company, not self-served.
  class LoansController < ApplicationController
    def index
      @loans = Loan.where(user_id: hr_current_user.id).order(starts_on: :desc)
      @outstanding = @loans.sum(BigDecimal(0), &:outstanding)
      @next_month = Date.current.next_month.beginning_of_month
    end
  end
end
