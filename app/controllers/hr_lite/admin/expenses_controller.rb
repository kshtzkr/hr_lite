module HrLite
  module Admin
    # The other side of the claim: decide it, then say when it was paid.
    class ExpensesController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_deciding!

      def index
        @status = params[:status].presence_in(Expense::STATUSES) || "submitted"
        scope = Expense.where(status: @status).includes(:user, :category).recent_first
        @expenses = paginate(hr_scope(scope, "expense.approve").where.not(user_id: hr_current_user.id))
      end

      def approve
        expense = decidable.find(params[:id])
        expense.approve!(actor: hr_current_user, note: params[:decision_note].presence)
        redirect_to admin_expenses_path, notice: "Claim approved."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_expenses_path, alert: reason_for(e, "Only a submitted claim can be approved.")
      end

      def reject
        expense = decidable.find(params[:id])
        note = params[:decision_note].to_s.strip
        return redirect_to admin_expenses_path, alert: "A note is required to reject." if note.blank?

        expense.reject!(actor: hr_current_user, note: note)
        redirect_to admin_expenses_path, notice: "Claim rejected."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_expenses_path, alert: reason_for(e, "Only a submitted claim can be rejected.")
      end

      def reimburse
        expense = decidable.find(params[:id])
        month = parse_month_param(params[:period_month])
        expense.reimburse!(actor: hr_current_user, period_month: month)
        redirect_to admin_expenses_path, notice: "Will be paid with #{month.strftime('%B %Y')} payroll."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_expenses_path, alert: reason_for(e, "Only an approved claim can go on payroll, and only on a month not yet paid.")
      end

      # The receipt the employee had to upload, for the person deciding; same rules as a document download.
      def receipt
        expense = decidable.find(params[:id])
        raise ActiveRecord::RecordNotFound unless expense.receipt.attached?

        AuditLog.record!(action: "expense.receipt_viewed", subject: expense, actor: hr_current_user,
                         changes: { "owner" => HrLite.display_name(expense.user) })
        redirect_to Rails.application.routes.url_helpers.rails_blob_path(
          expense.receipt, disposition: "inline", only_path: true, expires_in: 5.minutes
        ), allow_other_host: false
      end

      private

      def require_deciding! = hr_require_permission!("expense.approve", scope: :team)

      # Nobody approves their own claim: team scope includes the approver.
      def decidable = hr_scope(Expense.all, "expense.approve").where.not(user_id: hr_current_user.id)
    end
  end
end
