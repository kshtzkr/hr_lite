module HrLite
  module Admin
    # HR sets someone's mode (reason required), within attendance.manage reach.
    class WorkModesController < BaseController
      def override
        employee = HrLite.user_klass.find(params[:user_id])
        hr_require_reach!("attendance.manage", employee)
        raise ActiveRecord::RecordNotFound if employee.id == hr_current_user.id

        result = WorkModeSwitch.call(user: employee, mode: params[:mode], source: "hr", actor: hr_current_user,
                                     params: params.permit(:title, :client, :destination, :reason, :minutes, :until, :category))
        flash_for = result.ok? ? { notice: "#{hr_display_name(employee)} is now: #{result.event.label}." } : { alert: result.error }
        redirect_back fallback_location: admin_attendance_path(employee.id), **flash_for
      end
    end
  end
end
