module HrLite
  module Admin
    # One-off payslip lines: a bonus, an incentive, arrears, a reimbursement,
    # a one-time deduction. Money tier, like loans — this is somebody's pay.
    # Create and destroy are audited by PayrollLineItem's Audited concern.
    class PayrollLineItemsController < SuperadminController
      def index
        @month = parse_month_param(params[:month])
        @items = paginate(PayrollLineItem.for_month(@month).includes(:user, :component).order(:created_at))
      end

      def new
        @item = PayrollLineItem.new(period_month: parse_month_param(params[:month]))
      end

      def create
        @item = PayrollLineItem.new(item_params.merge(
          period_month: parse_month_param(params.dig(:payroll_line_item, :period_month)),
          created_by_id: hr_current_user.id,
          # Same list the form offers: loan repayments come from the loan itself.
          component: addable_components.find_by(id: params.dig(:payroll_line_item, :component_id))
        ))
        if @item.save
          redirect_to admin_payroll_line_items_path(month: @item.period_month.strftime("%Y-%m")),
                      notice: "#{@item.component.label} added for #{HrLite.display_name(@item.user)}."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def destroy
        item = PayrollLineItem.find(params[:id])
        removed = item.destroy
        redirect_to admin_payroll_line_items_path(month: item.period_month.strftime("%Y-%m")), status: :see_other,
                    **(removed ? { notice: "Removed." } : { alert: "That month has already been paid — it can't change now." })
      end

      private

      def item_params
        params.require(:payroll_line_item).permit(:user_id, :amount, :note)
      end

      def addable_components = SalaryComponent.active.where.not(code: "loan_repayment")
    end
  end
end
