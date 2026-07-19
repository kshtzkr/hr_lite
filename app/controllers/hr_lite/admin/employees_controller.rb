module HrLite
  module Admin
    # Employee HR profiles (leadership). Onboarding can create the login
    # itself (config.onboard_user); offboarding stamps the exit date and
    # revokes access (config.offboard_user) — nothing is ever deleted,
    # payroll history is a statutory record.
    class EmployeesController < LeadershipController
      def index
        @profiles = paginate(EmployeeProfile.includes(:user).order(:employee_code))
        @users_without_profile = HrLite.employees.reject { |u| EmployeeProfile.exists?(user_id: u.id) }
        @pending_resignations = Resignation.pending.includes(:user).recent_first
      end

      def show
        @profile = EmployeeProfile.includes(:user).find(params[:id])
        @structures = SalaryStructure.where(user_id: @profile.user_id).order(effective_from: :desc)
        @pending_resignation = Resignation.pending.find_by(user_id: @profile.user_id)
      end

      def new
        @profile = EmployeeProfile.new(user_id: params[:user_id], date_of_joining: Date.current)
      end

      def create
        new_login = params.dig(:employee_profile, :new_user_email).present?
        @profile = EmployeeProfile.new(profile_params)

        if new_login
          user = HrLite.config.onboard_user.call(
            name: params.dig(:employee_profile, :new_user_name).to_s,
            email: params.dig(:employee_profile, :new_user_email).to_s.strip,
            password: params.dig(:employee_profile, :new_user_password).to_s
          )
          @profile.user_id = user.id
        end

        if @profile.save
          if new_login
            invite_url = HrLite.config.invite_url_for&.call(@profile.user)
            Notifications.publish(
              "employee.onboarded",
              title: "Welcome aboard — your HR account is ready",
              body: invite_url ? "Set your password with the button below, then sign in with your email."
                               : "Sign in with your email; your manager has your starting password.",
              path: "/",
              link_url: invite_url,
              bell_to: [ @profile.user ],
              email_to: [ @profile.user ]
            )
          end
          redirect_to admin_employee_path(@profile), notice: "Employee #{'onboarded' if new_login} profile created."
        else
          render :new, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordInvalid => e
        @profile.errors.add(:base, "Could not create the login: #{e.record.errors.full_messages.to_sentence}")
        render :new, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique
        @profile.errors.add(:base, "Could not create the login: that email already has an account")
        render :new, status: :unprocessable_entity
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

      # Exit: stamps the date (attendance/payroll clip on it) and revokes
      # access via the host hook. Audited via the profile update.
      def offboard
        @profile = EmployeeProfile.find(params[:id])
        exit_date = params[:date_of_exit].presence&.to_date || Date.current

        @profile.update!(date_of_exit: exit_date)
        begin
          HrLite.config.offboard_user.call(@profile.user)
        rescue => e
          Rails.logger.error("[hr_lite] offboard_user failed: #{e.class}: #{e.message}")
        end
        redirect_to admin_employee_path(@profile),
                    notice: "Offboarded — last day #{exit_date.strftime('%d %b %Y')}, access revoked."
      end

      private

      def profile_params
        params.require(:employee_profile).permit(
          :user_id, :manager_id, :employee_code, :designation, :date_of_birth, :date_of_joining,
          :date_of_exit, :department, :work_location, :pan_number, :pf_uan, :esi_number,
          :bank_account_number, :bank_ifsc, :bank_name, :tax_regime, :declared_annual_deductions
        )
      end
    end
  end
end
