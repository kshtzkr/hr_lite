module HrLite
  module Admin
    # salary.manage, not payroll.manage: HR sets structures without running payroll.
    class SalaryStructuresController < SuperadminController
      skip_before_action :require_money_access!
      before_action -> { hr_require_permission!("salary.manage", scope: :all) }
      before_action :set_profile

      def new
        @structure = SalaryStructure.new(user_id: @profile.user_id,
                                         effective_from: Date.current.beginning_of_month)
      end

      def create
        @structure = SalaryStructure.new(structure_params.merge(
          user_id: @profile.user_id, created_by_id: hr_current_user.id
        ))
        if @structure.save(context: :ctc_form)
          redirect_to admin_employee_path(@profile), notice: "Salary structure saved."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @structure = SalaryStructure.where(user_id: @profile.user_id).find(params[:id])
      end

      def update
        @structure = SalaryStructure.where(user_id: @profile.user_id).find(params[:id])
        @structure.assign_attributes(structure_params)
        if @structure.save(context: :ctc_form)
          redirect_to admin_employee_path(@profile), notice: "Salary structure updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_profile
        @profile = EmployeeProfile.find(params[:employee_id])
      end

      def structure_params
        params.require(:salary_structure).permit(
          :annual_ctc, :effective_from, :metro,
          :pf_applicable, :pf_on_full_basic, :esi_applicable, :pt_state, :notes
        )
      end
    end
  end
end
