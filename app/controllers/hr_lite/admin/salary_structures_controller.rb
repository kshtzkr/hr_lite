module HrLite
  module Admin
    class SalaryStructuresController < SuperadminController
      before_action :set_profile

      def new
        @structure = SalaryStructure.new(user_id: @profile.user_id,
                                         effective_from: Date.current.beginning_of_month)
      end

      def create
        @structure = SalaryStructure.new(structure_params.merge(
          user_id: @profile.user_id, created_by_id: hr_current_user.id
        ))
        return fill_from_ctc(:new) if params[:fill_from_ctc]

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
        @structure.assign_attributes(structure_params)
        return fill_from_ctc(:edit) if params[:fill_from_ctc]

        if @structure.save
          redirect_to admin_employee_path(@profile), notice: "Salary structure updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      # Shows the split for a check; only the Save button writes it.
      def fill_from_ctc(view)
        @structure.fill_from_ctc
        return render(view, status: :unprocessable_entity) unless @structure.valid?

        flash.now[:notice] = "Filled from CTC — check the lines, then Save."
        render view
      end

      def set_profile
        @profile = EmployeeProfile.find(params[:employee_id])
      end

      def structure_params
        params.require(:salary_structure).permit(
          :annual_ctc, :effective_from, :basic, :hra, :special_allowance, :other_earnings,
          :pf_applicable, :pf_on_full_basic, :esi_applicable, :pt_state, :notes
        )
      end
    end
  end
end
