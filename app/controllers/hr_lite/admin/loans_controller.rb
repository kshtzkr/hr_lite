module HrLite
  module Admin
    # Loans and salary advances. Money tier: the instalment lands as a
    # deduction on a payslip, so whoever sets it is setting somebody's pay.
    class LoansController < SuperadminController
      def index
        @status = params[:status].presence_in(Loan::STATUSES) || "active"
        @loans = paginate(Loan.includes(:user).where(status: @status).order(starts_on: :desc))
        @outstanding = Loan.active.includes(:loan_repayments).sum(BigDecimal(0), &:outstanding)
      end

      def new
        @loan = Loan.new(starts_on: Date.current.next_month.beginning_of_month)
      end

      def create
        @loan = Loan.new(loan_params.merge(approved_by_id: hr_current_user.id))
        if @loan.save
          redirect_to admin_loans_path,
                      notice: "Loan recorded for #{HrLite.display_name(@loan.user)} — " \
                              "deductions start #{@loan.starts_on.strftime('%b %Y')}."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def show
        @loan = Loan.includes(:loan_repayments).find(params[:id])
      end

      # Closing stops the deduction. It does NOT delete the repayments —
      # those are on published payslips and are what the outstanding balance
      # is derived from.
      def close
        loan = Loan.find(params[:id])
        loan.update!(status: "closed")
        redirect_to admin_loans_path, notice: "Closed — no further deductions."
      end

      def cancel
        loan = Loan.find(params[:id])
        if loan.loan_repayments.exists?
          return redirect_to admin_loan_path(loan),
                             alert: "Instalments have already been deducted. Close it instead — " \
                                    "cancelling would deny money that has left somebody's salary."
        end

        loan.update!(status: "cancelled")
        redirect_to admin_loans_path, notice: "Cancelled before any deduction."
      end

      private

      def loan_params
        params.require(:loan).permit(:user_id, :principal, :monthly_instalment, :starts_on, :reason)
      end
    end
  end
end
