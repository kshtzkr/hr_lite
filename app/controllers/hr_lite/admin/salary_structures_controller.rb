module HrLite
  module Admin
    class SalaryStructuresController < LeadershipController
      before_action :set_profile

      def new
        @structure = SalaryStructure.new(user_id: @profile.user_id,
                                         effective_from: Date.current.beginning_of_month)
      end

      def create
        @structure = SalaryStructure.new(structure_params.merge(
          user_id: @profile.user_id, created_by_id: hr_current_user.id
        ))
        if @structure.save
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
        if @structure.update(structure_params)
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
          :effective_from, :basic, :hra, :special_allowance, :other_earnings,
          :pf_applicable, :pf_on_full_basic, :esi_applicable, :pt_state, :notes
        )
      end
    end
  end
end
