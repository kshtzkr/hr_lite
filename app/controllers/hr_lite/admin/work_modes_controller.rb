module HrLite
  module Admin
    # Who is in which mode (live today, "during the day" for past dates), who
    # needs a look, field check-ins, one person's timeline, and HR override.
    # Locations and trip details show here only, inside attendance.view reach.
    class WorkModesController < BaseController
      def index
        @date = params[:date].present? ? parse_date_param(params[:date]) : Date.current
        visible = hr_access.visible_user_ids("attendance.view")
        employees = HrLite.active_employees(on: @date)
        employees = employees.select { |u| visible.include?(u.id) } if visible
        if (dept = params[:department].presence)
          in_dept = EmployeeProfile.where(department: dept).pluck(:user_id).to_set
          employees = employees.select { |u| in_dept.include?(u.id) }
        end
        @departments = EmployeeProfile.where.not(department: [ nil, "" ]).distinct.order(:department).pluck(:department)
        ids = employees.map(&:id)
        @people = employees.index_by(&:id)

        @by_mode = @date == Date.current ? live_modes(ids) : day_modes(ids)
        records = AttendanceRecord.for_date(@date).where(user_id: ids).index_by(&:user_id)
        on_leave = LeaveRequest.active_on(@date).where(user_id: ids, half_day: false).pluck(:user_id).to_set
        working_day = WorkingCalendar.new(@date..@date).working_day?(@date) && @date <= Date.current
        @needs_review = working_day ? ids.reject { |id| on_leave.include?(id) || records[id]&.check_in_at } : []
        @field = records.values.select { |r| %w[travelling outside_meeting].include?(r.work_mode) }
        @field_events = WorkModeEvent.where(attendance_record_id: @field.map(&:id), source: "system", mode: %w[travelling outside_meeting])
                                     .index_by(&:attendance_record_id)

        if (@person = params[:user_id].presence && @people[params[:user_id].to_i])
          day = @date.in_time_zone(HrLite.config.time_zone).all_day
          @timeline = WorkModeEvent.where(user_id: @person.id).where("started_at <= ? AND (ended_at IS NULL OR ended_at >= ?)", day.last, day.first)
                                   .order(:started_at, :id).limit(200)
          @locations = WorkLocation.where(id: @timeline.filter_map(&:work_location_id)).index_by(&:id)
        end
      end

      def override
        employee = HrLite.user_klass.find(params[:user_id])
        hr_require_reach!("attendance.manage", employee)
        raise ActiveRecord::RecordNotFound if employee.id == hr_current_user.id

        result = WorkModeSwitch.call(user: employee, mode: params[:mode], source: "hr", actor: hr_current_user,
                                     params: params.permit(:title, :client, :destination, :reason, :minutes, :until, :category))
        flash_for = result.ok? ? { notice: "#{hr_display_name(employee)} is now: #{result.event.label}." } : { alert: result.error }
        redirect_back fallback_location: admin_attendance_path(employee.id), **flash_for
      end

      private

      # mode => user ids, from the live status (primary and overlay both count).
      def live_modes(ids)
        WorkStatus.for_users(ids).each_with_object(Hash.new { |h, k| h[k] = [] }) do |(id, st), out|
          out[st.primary.mode] << id
          out[st.overlay.mode] << id if st.overlay
        end
      end

      # A past date: everyone who spent any time in each mode that day.
      def day_modes(ids)
        day = @date.in_time_zone(HrLite.config.time_zone).all_day
        rows = WorkModeEvent.where(user_id: ids).where("started_at <= ? AND (ended_at IS NULL OR ended_at >= ?)", day.last, day.first)
                            .distinct.pluck(:mode, :user_id)
        out = rows.group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
        out["on_leave"] = LeaveRequest.active_on(@date).where(user_id: ids, half_day: false).pluck(:user_id).uniq
        out
      end
    end
  end
end
