module HrLite
  module Admin
    # Work-time analytics for HR: one person (audited) or a department
    # aggregate. Needs work_analytics.view; its scope decides whose rows.
    class WorkTimeController < BaseController
      before_action do
        raise ActiveRecord::RecordNotFound unless HrLite.config.office_geofence
        hr_access_denied unless hr_can?("work_analytics.view", scope: :team)
      end

      def index
        @period, @period_error = WorkModeDurations::Period.from_params(params, Date.current)
        visible = hr_access.visible_user_ids("work_analytics.view")
        @employees = HrLite.employees.reject { |u| visible && !visible.include?(u.id) }
        @departments = EmployeeProfile.where(user_id: @employees.map(&:id)).where.not(department: [ nil, "" ])
                                      .distinct.order(:department).pluck(:department)
        if (dept = params[:department].presence)
          in_dept = EmployeeProfile.where(department: dept).pluck(:user_id).to_set
          @employees = @employees.select { |u| in_dept.include?(u.id) }
        end
        @names = @employees.to_h { |u| [ u.id, hr_display_name(u) ] }

        if params[:user_id].present?
          @person = HrLite.user_klass.find(params[:user_id])
          hr_require_reach!("work_analytics.view", @person)
          @names[@person.id] = hr_display_name(@person)
          ids = [ @person.id ]
          AuditLog.record!(action: "work_analytics.viewed", subject: @person, actor: hr_current_user,
                           changes: { "period" => @period.label })
        else
          ids = @employees.map(&:id)
        end

        @result = WorkModeDurations.call(ids, @period)
        @records = @person ? AttendanceRecord.includes(:work_location, :check_out_work_location).where(user_id: @person.id, date: @period.from..@period.to).where.not(check_in_at: nil).order(:date).limit(400) : []
      end
    end
  end
end
