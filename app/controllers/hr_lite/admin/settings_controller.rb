module HrLite
  module Admin
    class SettingsController < LeadershipController
      def edit
        @setting = Setting.instance
      end

      def update
        @setting = Setting.instance
        if @setting.update(params.require(:setting).permit(:weekend_policy, :employee_code_prefix))
          redirect_to edit_admin_setting_path, notice: "Settings saved."
        else
          render :edit, status: :unprocessable_entity
        end
      end
    end
  end
end
