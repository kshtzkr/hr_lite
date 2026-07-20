module HrLite
  module Admin
    class PayrollRunsController < SuperadminController
      def index
        @runs = paginate(PayrollRun.recent_first)
      end

      def new
        @run = PayrollRun.new(period_month: Date.current.prev_month.beginning_of_month)
      end

      def create
        month = parse_month_param(params.dig(:payroll_run, :period_month))
        @run = PayrollRun.new(period_month: month, created_by_id: hr_current_user.id,
                              notes: params.dig(:payroll_run, :notes))
        if @run.save
          redirect_to admin_payroll_run_path(@run), notice: "Run created — compute when ready."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def show
        @run = PayrollRun.find(params[:id])
        @slips = @run.salary_slips.includes(:user).sort_by { |slip| HrLite.display_name(slip.user) }
      end

      def destroy
        run = PayrollRun.find(params[:id])
        if run.destroy
          redirect_to admin_payroll_runs_path, notice: "Draft run deleted.", status: :see_other
        else
          redirect_to admin_payroll_run_path(run), alert: run.errors.full_messages.to_sentence,
                      status: :see_other
        end
      end

      def compute
        transition { |run| run.compute!(actor: hr_current_user) && "Computed — review the slips." }
      end

      def finalize
        transition { |run| run.finalize!(actor: hr_current_user) && "Run finalized." }
      end

      def unlock
        transition { |run| run.unlock!(actor: hr_current_user) && "Back in review." }
      end

      def publish
        transition { |run| run.publish!(actor: hr_current_user) && "Published — employees notified." }
      end

      # Payout register: the full money sheet including bank details —
      # deliberately leadership-only PII.
      def register
        run = PayrollRun.find(params[:id])
        send_data register_csv(run), filename: "payroll-register-#{run.period_month.strftime('%Y-%m')}.csv",
                                     type: "text/csv"
      end

      private

      def transition
        run = PayrollRun.find(params[:id])
        notice = yield(run)
        redirect_to admin_payroll_run_path(run), notice: notice
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_payroll_run_path(run), alert: "That step is not available from #{run.status}."
      end

      def register_csv(run)
        require "csv"
        CSV.generate do |csv|
          csv << [ "Code", "Name", "Days", "LOP", "Gross", "PF", "ESI", "PT", "TDS",
                   "Net pay", "Bank", "Account", "IFSC" ]
          run.salary_slips.includes(:user).each do |slip|
            profile = slip.user_profile
            deductions = slip.deductions_rows.index_by { |row| row["code"] }
            csv << [
              profile&.employee_code, HrLite.display_name(slip.user),
              slip.payable_days, slip.effective_lop_days,
              slip.gross_earnings, deductions.dig("pf_employee", "amount") || 0,
              deductions.dig("esi_employee", "amount") || 0, deductions.dig("pt", "amount") || 0,
              deductions.dig("tds", "amount") || 0, slip.net_pay,
              profile&.bank_name, profile&.bank_account_number, profile&.bank_ifsc
            ]
          end
        end
      end
    end
  end
end
