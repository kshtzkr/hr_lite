module HrLite
  module Admin
    class AttendancesController < BaseController
      # Team day view: everyone × their punch/status for one date.
      def index
        @date = parse_date_param(params[:date])
        # A manager's board is their reports; HR's is the company. Both read
        # the same screen — the difference is one permission scope.
        visible = hr_access.visible_user_ids("attendance.view")
        @employees = HrLite.employees
        @employees = @employees.select { |user| visible.include?(user.id) } if visible
        @records = AttendanceRecord.for_date(@date).where(user_id: @employees.map(&:id)).index_by(&:user_id)
        @flagged_count = @records.values.count(&:flagged?)
        # "How many people punched where": off-site punches count as one place.
        @offices = OfficeLocation.active.to_a
        @places = %i[check_in check_out].index_with do |side|
          @records.values.select { |r| r.public_send("#{side}_at") }.map do |r|
            OfficeLocation.place(r.public_send("#{side}_lat"), r.public_send("#{side}_lng"), @offices)&.split(" · ")&.first || "No GPS"
          end.tally
        end
      end

      # Mon–Fri hours per person (Saturday never counts) against
      # config.work_hours[:week], pro rata for holidays and full-day leave.
      # The current week counts only the days already over.
      def week
        @monday = parse_date_param(params[:date]).beginning_of_week(:monday)
        calendar = WorkingCalendar.new(@monday..(@monday + 4))
        days = (@monday..[ @monday + 4, Date.current - 1 ].min).select { |d| calendar.working_day?(d) }
        visible = hr_access.visible_user_ids("attendance.view")
        employees = HrLite.active_employees(on: @monday)
        employees = employees.select { |user| visible.include?(user.id) } if visible
        records = AttendanceRecord.where(user_id: employees.map(&:id), date: days).group_by(&:user_id)
        on_leave = days.index_with { |d| LeaveRequest.active_on(d).where(half_day: false).pluck(:user_id) }
        week_hours = HrLite.config.work_hours&.dig(:week)

        @rows = employees.map do |user|
          worked = records.fetch(user.id, []).filter_map(&:worked_duration)
          hours = worked.sum / 3600.0
          target = week_hours && week_hours * days.count { |d| on_leave[d].exclude?(user.id) } / 5.0
          { user: user, hours: hours, avg: worked.any? ? hours / worked.size : nil, target: target,
            below: target.present? && target.positive? && hours < target }
        end
      end

      # One employee's month + the regularization form for ?date=.
      def show
        @employee = find_visible_employee
        @month = parse_month_param(params[:month])
        @day_status = DayStatus.new(user: @employee, range: @month.beginning_of_month..@month.end_of_month)
        @counts = @day_status.counts
        @counts[:absent] -= 1 if @month.all_month.cover?(Date.current) && @day_status.for(Date.current).kind == :absent
        @edit_date = params[:date].present? ? parse_date_param(params[:date]) : nil
        @edit_record = @edit_date && AttendanceRecord.find_or_initialize_by(user_id: @employee.id, date: @edit_date)
        @punches = AttendanceRecord.for_month(@month).where(user_id: @employee.id).where.not(check_in_at: nil).order(:date)
        @offices = OfficeLocation.active.to_a
      end

      # Regularization: fix punches with a mandatory note, fully audited.
      # Clearing both punch times deletes the record (that is how an
      # erroneous punch is removed).
      def update
        @employee = find_manageable_employee
        date = parse_date_param(params[:date])
        record = AttendanceRecord.find_or_initialize_by(user_id: @employee.id, date: date)

        note = params.dig(:attendance_record, :regularization_note).to_s.strip
        if note.blank?
          return redirect_to admin_attendance_path(@employee.id, date: date, month: date.strftime("%Y-%m")),
                             alert: "A regularization note is required."
        end

        attrs = params.require(:attendance_record).permit(:check_in_at, :check_out_at, :status, :half_day_part)
        if attrs[:check_in_at].blank? && attrs[:check_out_at].blank?
          # Nothing to remove used to still write a `destroy` audit row with
          # subject_id 0 and email the employee that a punch was removed.
          unless record.persisted?
            return redirect_to admin_attendance_path(@employee.id, month: date.strftime("%Y-%m")),
                               notice: "Nothing to remove for that day."
          end

          record.destroy
          log_regularization(record, note, removed: true)
          return redirect_to admin_attendance_path(@employee.id, month: date.strftime("%Y-%m")),
                             notice: "Punch removed."
        end

        # A check-out with no check-in produces a row every consumer reads as
        # absent (they all key off check_in_at), so the day silently stays LOP
        # while the screen reports the fix succeeded.
        if attrs[:check_in_at].blank?
          return redirect_to admin_attendance_path(@employee.id, date: date, month: date.strftime("%Y-%m")),
                             alert: "A check-in time is required when a check-out is set."
        end

        record.assign_attributes(attrs)
        record.half_day_part = attrs[:half_day_part].presence if attrs.key?(:half_day_part)
        record.status = record.half_day_part ? "half_day" : "present" if attrs.key?(:half_day_part)
        record.status = "present" if record.status.blank?
        record.regularized_by_id = hr_current_user.id
        record.regularized_at = Time.current
        record.regularization_note = note

        if record.save
          log_regularization(record, note, removed: false)
          redirect_to admin_attendance_path(@employee.id, month: date.strftime("%Y-%m")),
                      notice: "Attendance updated."
        else
          redirect_to admin_attendance_path(@employee.id, date: date, month: date.strftime("%Y-%m")),
                      alert: record.errors.full_messages.to_sentence
        end
      end

      private

      # Viewing somebody's month and rewriting their punches are different
      # authorities, so they resolve through different permissions — a role
      # can be given the board without being given the pencil.
      def find_visible_employee = employee_within("attendance.view")
      # Nobody rewrites their own punches: team and company scope include the holder.
      def find_manageable_employee = employee_within("attendance.manage").tap { |e| raise ActiveRecord::RecordNotFound if e.id == hr_current_user.id }

      def employee_within(permission)
        employee = HrLite.user_klass.find(params[:user_id])
        hr_require_reach!(permission, employee)
        employee
      end

      def log_regularization(record, note, removed:)
        AuditLog.record!(
          action: removed ? "destroy" : "regularize", subject: record, actor: hr_current_user,
          changes: { "date" => record.date.to_s, "note" => note }
        )
        Notifications.publish(
          "attendance.regularized",
          title: "Attendance #{removed ? 'punch removed' : 'regularized'} for #{record.date.strftime('%d %b')}",
          body: note,
          path: "/attendance?month=#{record.date.strftime('%Y-%m')}",
          bell_to: [ record.user ],
          email_to: [ record.user ]
        )
      end
    end
  end
end
