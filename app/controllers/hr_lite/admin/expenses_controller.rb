module HrLite
  module Admin
    # The other side of the claim: decide it, then say when it was paid.
    class ExpensesController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_deciding!

      def index
        @status = params[:status].presence_in(Expense::STATUSES) || "submitted"
        scope = Expense.where(status: @status).includes(:user, :category).recent_first
        @expenses = paginate(hr_scope(scope, "expense.approve"))
      end

      def approve
        expense = decidable.find(params[:id])
        expense.approve!(actor: hr_current_user, note: params[:decision_note].presence)
        redirect_to admin_expenses_path, notice: "Claim approved."
      end

      def reject
        expense = decidable.find(params[:id])
        note = params[:decision_note].to_s.strip
        return redirect_to admin_expenses_path, alert: "A note is required to reject." if note.blank?

        expense.reject!(actor: hr_current_user, note: note)
        redirect_to admin_expenses_path, notice: "Claim rejected."
      end

      def reimburse
        expense = decidable.find(params[:id])
        month = parse_month_param(params[:period_month])
        expense.reimburse!(actor: hr_current_user, period_month: month)
        redirect_to admin_expenses_path, notice: "Marked reimbursed with #{month.strftime('%B %Y')}."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_expenses_path, alert: "Only an approved claim can be reimbursed."
      end

      private

      def require_deciding! = hr_require_permission!("expense.approve", scope: :team)

      def decidable = hr_scope(Expense.all, "expense.approve")
    end
  end
end
