module HrLite
  module Admin
    class SettingsController < LeadershipController
      def edit
        @setting = Setting.instance
      end

      def update
        @setting = Setting.instance
        if @setting.update(params.require(:setting).permit(:weekend_policy, :employee_code_prefix, :lunch_break_minutes, :short_break_minutes,
                                                          :day_minutes, :half_day_below_minutes, :recheck_in_from, :recheck_in_until))
          redirect_to edit_admin_setting_path, notice: "Settings saved."
        else
          render :edit, status: :unprocessable_entity
        end
      end
    end
  end
end
