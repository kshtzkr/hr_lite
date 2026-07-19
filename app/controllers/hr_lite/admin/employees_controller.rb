module HrLite
  module Admin
    # Employee HR profiles (leadership). No destroy — exits are a date;
    # payroll history is a statutory record.
    class EmployeesController < LeadershipController
      def index
        @profiles = paginate(EmployeeProfile.includes(:user).order(:employee_code))
        @users_without_profile = HrLite.employees.reject { |u| EmployeeProfile.exists?(user_id: u.id) }
      end

      def show
        @profile = EmployeeProfile.includes(:user).find(params[:id])
        @structures = SalaryStructure.where(user_id: @profile.user_id).order(effective_from: :desc)
      end

      def new
        @profile = EmployeeProfile.new(user_id: params[:user_id], date_of_joining: Date.current)
      end

      def create
        @profile = EmployeeProfile.new(profile_params)
        if @profile.save
          redirect_to admin_employee_path(@profile), notice: "Employee profile created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @profile = EmployeeProfile.find(params[:id])
      end

      def update
        @profile = EmployeeProfile.find(params[:id])
        if @profile.update(profile_params)
          redirect_to admin_employee_path(@profile), notice: "Employee profile updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def profile_params
        params.require(:employee_profile).permit(
          :user_id, :employee_code, :designation, :date_of_birth, :date_of_joining,
          :date_of_exit, :department, :work_location, :pan_number, :pf_uan, :esi_number,
          :bank_account_number, :bank_ifsc, :bank_name, :tax_regime, :declared_annual_deductions
        )
      end
    end
  end
end
