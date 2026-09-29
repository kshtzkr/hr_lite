module HrLite
  module Admin
    # No destroy: claims hold the category by foreign key. Retire one by
    # unticking Active, which takes it off the claim form.
    class ExpenseCategoriesController < LeadershipController
      def index
        @expense_categories = ExpenseCategory.alphabetical
      end

      def new
        @expense_category = ExpenseCategory.new
      end

      def create
        @expense_category = ExpenseCategory.new(expense_category_params)
        if @expense_category.save
          redirect_to admin_expense_categories_path, notice: "Category added."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @expense_category = ExpenseCategory.find(params[:id])
      end

      def update
        @expense_category = ExpenseCategory.find(params[:id])
        if @expense_category.update(expense_category_params)
          redirect_to admin_expense_categories_path, notice: "Category updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def expense_category_params
        params.require(:expense_category).permit(:name, :monthly_cap, :receipt_required, :active)
      end
    end
  end
end
