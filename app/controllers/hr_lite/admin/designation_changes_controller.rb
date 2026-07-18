module HrLite
  module Admin
    # Standalone role change (promotion without an appraisal).
    class DesignationChangesController < LeadershipController
      before_action :set_profile

      def new
        @change = DesignationChange.new(user_id: @profile.user_id, effective_date: Date.current)
      end

      def create
        @change = DesignationChange.new(change_params.merge(
          user_id: @profile.user_id, created_by_id: hr_current_user.id
        ))
        if @change.save
          redirect_to admin_employee_path(@profile), notice: "Role change recorded."
        else
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_profile
        @profile = EmployeeProfile.find(params[:employee_id])
      end

      def change_params
        params.require(:designation_change).permit(:to_designation, :effective_date, :note)
      end
    end
  end
end
