module HrLite
  module Admin
    # Performance improvement plans: the appraisal tier, so Super Admin only.
    class PerformancePlansController < SuperadminController
      before_action :set_plan, only: %i[edit update]

      def index
        @plans = paginate(PerformancePlan.includes(:user).open_first)
      end

      def new
        @plan = PerformancePlan.new(user_id: params[:user_id], start_date: Date.current, end_date: Date.current + 30)
      end

      def create
        @plan = PerformancePlan.new(plan_params.merge(created_by_id: hr_current_user.id))
        if @plan.save
          redirect_to admin_performance_plans_path, notice: "PIP started."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @plan.update(plan_params.except(:user_id))
          redirect_to admin_performance_plans_path, notice: "PIP updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_plan
        @plan = PerformancePlan.find(params[:id])
        redirect_to admin_performance_plans_path, alert: "A closed PIP cannot be changed." if @plan.closed?
      end

      def plan_params
        params.require(:performance_plan).permit(:user_id, :start_date, :end_date, :goals, :status, :outcome_note)
      end
    end
  end
end
