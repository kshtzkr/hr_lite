module HrLite
  module Admin
    # The CA's year-end pass over every slip and declaration. Reviewers
    # (payroll.verify) verify or flag; approvers and payroll resolve flags.
    class CaReviewsController < BaseController
      skip_before_action :require_operations_access!
      before_action -> { require_any!("payroll.verify", "payroll.approve", "payroll.manage") }, only: :index
      before_action -> { require_any!("payroll.verify") }, only: %i[verify flag verify_all]
      before_action -> { require_any!("payroll.approve", "payroll.manage") }, only: :resolve

      def index
        @fy = FinancialYear.start_for(params[:fy].present? ? parse_date_param(params[:fy]) : Date.current)
        @tab = params[:tab] == "declarations" ? "declarations" : "slips"
        @status = params[:status].presence_in(%w[unreviewed verified flagged resolved])
        scope = @tab == "slips" ? CaReview.slips_for(@fy).includes(:user, :payroll_run).order("hr_lite_payroll_runs.period_month", :user_id) : CaReview.declarations_for(@fy).includes(:user).order(:user_id)
        type = scope.klass.name
        reviewed = CaReview.where(subject_type: type)
        scope = if @status == "unreviewed"
          scope.where.not(id: reviewed.select(:subject_id))
        elsif @status
          scope.where(id: reviewed.where(status: @status).select(:subject_id))
        else
          scope
        end
        @rows = paginate(scope)
        @reviews = reviewed.where(subject_id: @rows.map(&:id)).index_by(&:subject_id)
        @left = CaReview.outstanding(@fy)
        @totals = { "slips" => CaReview.slips_for(@fy).count, "declarations" => CaReview.declarations_for(@fy).count }
      end

      def verify
        CaReview.verify!(subject, actor: hr_current_user)
        redirect_back_to_list notice: "Verified."
      end

      def flag
        return redirect_back_to_list(alert: "Say what is wrong — HR has to know what to fix.") if params[:note].blank?

        CaReview.flag!(subject, actor: hr_current_user, note: params[:note])
        redirect_back_to_list notice: "Flagged — HR and payroll have been told."
      end

      # "Verify all shown": the unreviewed rows on the page the CA was looking at.
      def verify_all
        model = params[:subject_type] == "HrLite::TaxDeclaration" ? TaxDeclaration : SalarySlip
        reviewed = CaReview.where(subject_type: model.name, subject_id: params[:ids]).pluck(:subject_id)
        model.where(id: Array(params[:ids]) - reviewed.map(&:to_s)).find_each { |s| CaReview.verify!(s, actor: hr_current_user) }
        redirect_back_to_list notice: "Verified everything shown."
      end

      def resolve
        CaReview.find(params[:id]).resolve!(actor: hr_current_user, note: params[:note])
        redirect_back_to_list notice: "Marked resolved."
      rescue ActiveRecord::RecordInvalid
        redirect_back_to_list alert: "Only a flagged item can be resolved."
      end

      private

      def require_any!(*keys)
        return if keys.any? { |key| hr_can?(key, scope: :all) }

        hr_require_permission!(keys.first, scope: :all)
      end

      def subject
        model = params[:subject_type] == "HrLite::TaxDeclaration" ? TaxDeclaration : SalarySlip
        model.find(params[:subject_id])
      end

      def redirect_back_to_list(**flash)
        redirect_to admin_ca_reviews_path(params.permit(:fy, :tab, :status, :page).to_h), **flash
      end
    end
  end
end
