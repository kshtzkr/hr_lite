module HrLite
  # An employee's own claims. Scoped to the signed-in person the same way
  # every other self-service screen is: a foreign id 404s through the
  # relation rather than 403ing.
  class ExpensesController < ApplicationController
    before_action :require_claiming!

    def index
      @expenses = paginate(own.includes(:category).recent_first)
      @categories = ExpenseCategory.active.alphabetical
    end

    def new
      @expense = Expense.new(spent_on: Date.current)
      @categories = ExpenseCategory.active.alphabetical
    end

    def create
      @expense = Expense.new(expense_params.merge(user_id: hr_current_user.id))
      if @expense.save
        @expense.submit!(actor: hr_current_user)
        redirect_to expenses_path, notice: "Claim submitted."
      else
        @categories = ExpenseCategory.active.alphabetical
        render :new, status: :unprocessable_entity
      end
    end

    def cancel
      expense = own.find(params[:id])
      if expense.draft? || expense.submitted?
        expense.update!(status: "cancelled")
        expense.approval_route.cancel_all!
        redirect_to expenses_path, notice: "Claim withdrawn."
      else
        redirect_to expenses_path, alert: "Only a claim still waiting can be withdrawn."
      end
    end

    private

    def require_claiming! = hr_require_permission!("expense.claim")

    def own = Expense.where(user_id: hr_current_user.id)

    def expense_params
      params.require(:expense).permit(:category_id, :amount, :spent_on, :description, :receipt)
    end
  end
end
