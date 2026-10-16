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
        @penalty_minutes = AttendancePenalty.held_minutes(@employees.map(&:id))
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
        span = @monday..[ @monday + 4, Date.current - 1 ].min
        calendars = WorkingCalendar.by_office(@monday..(@monday + 4))
        visible = hr_access.visible_user_ids("attendance.view")
        employees = HrLite.active_employees(on: @monday)
        employees = employees.select { |user| visible.include?(user.id) } if visible
        offices = EmployeeProfile.where(user_id: employees.map(&:id)).pluck(:user_id, :office_location_id).to_h
        records = AttendanceRecord.where(user_id: employees.map(&:id), date: span).group_by(&:user_id)
        on_leave = span.index_with { |d| LeaveRequest.active_on(d).where(half_day: false).pluck(:user_id) }
        week_hours = HrLite.config.work_hours&.dig(:week)

        @rows = employees.map do |user|
          # Each person's own working days: their office's holidays are off.
          days = span.select { |d| calendars[offices[user.id]].working_day?(d) }
          worked = records.fetch(user.id, []).select { |r| days.include?(r.date) }.filter_map(&:worked_duration)
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
        @punches = AttendanceRecord.for_month(@month).where(user_id: @employee.id).where.not(check_in_at: nil)
                                   .includes(:work_location, :check_out_work_location).order(:date)
        @offices = OfficeLocation.active.to_a
      end

      # Regularization: fix punches with a mandatory note, fully audited.
      # Clearing both punch times deletes the record (that is how an
      # erroneous punch is removed). Reset check-in does the same; reset
      # check-out leaves them checked in, so they can check in or out again.
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
        if params[:reset] == "check_in" || (attrs[:check_in_at].blank? && attrs[:check_out_at].blank?)
          # Nothing to remove used to still write a `destroy` audit row with
          # subject_id 0 and email the employee that a punch was removed.
          unless record.persisted?
            return redirect_to admin_attendance_path(@employee.id, month: date.strftime("%Y-%m")),
                               notice: "Nothing to remove for that day."
          end

          record.destroy
          # Its late penalties go too, so checking in again is not charged twice.
          AttendancePenalty.active.where(attendance_record_id: record.id)
                           .find_each { |p| p.update!(removed_at: Time.current, removed_by_id: hr_current_user.id, removal_reason: note) }
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
        record.clear_check_out if params[:reset] == "check_out"
        record.half_day_part = attrs[:half_day_part].presence if attrs.key?(:half_day_part)
        record.status = record.half_day_part ? "half_day" : "present" if attrs.key?(:half_day_part)
        record.status = "present" if record.status.blank?
        record.regularized_by_id = hr_current_user.id
        record.regularized_at = Time.current
        record.regularization_note = note

        if record.save
          log_regularization(record, note, removed: false)
          if params[:reset] == "check_out" && date == Date.current
            WorkModeEvent.start!(user_id: @employee.id, mode: record.work_mode || "office", source: "hr",
                                 actor: hr_current_user, attendance_record: record)
          end
          redirect_to admin_attendance_path(@employee.id, month: date.strftime("%Y-%m")),
                      notice: "Attendance updated."
        else
          redirect_to admin_attendance_path(@employee.id, date: date, month: date.strftime("%Y-%m")),
                      alert: record.errors.full_messages.to_sentence
        end
      end

      # HR sets a locked slot from today for the period.
      def slot
        @employee = find_manageable_employee
        period = params[:period].to_s
        slot = AttendanceSlot.new(user_id: @employee.id, set_by_id: hr_current_user.id, period: period,
                                  start_minute: params[:start_minute].to_i, starts_on: Date.current,
                                  ends_on: AttendanceSlot.ends_on_for(period, Date.current))
        flash_for = slot.save ? { notice: "Slot set to #{AttendanceSlot.label(slot.start_minute)}." } : { alert: slot.errors.full_messages.to_sentence }
        redirect_to admin_attendance_path(@employee.id), flash_for
      end

      # Lets the employee pick a new slot themselves.
      def unlock_slot
        @employee = find_manageable_employee
        AttendanceSlot.where(user_id: @employee.id, locked: true).where(ends_on: Date.current..).find_each { |s| s.update!(locked: false) }
        redirect_to admin_attendance_path(@employee.id), notice: "Slot unlocked. #{hr_display_name(@employee)} can pick a new one."
      end

      def remove_penalty
        @employee = find_manageable_employee
        penalty = AttendancePenalty.active.where(user_id: @employee.id).find(params[:penalty_id])
        reason = params[:removal_reason].to_s.strip
        month = penalty.date.strftime("%Y-%m")
        return redirect_to admin_attendance_path(@employee.id, month: month), alert: "A reason is required." if reason.blank?

        penalty.update!(removed_at: Time.current, removed_by_id: hr_current_user.id, removal_reason: reason)
        redirect_to admin_attendance_path(@employee.id, month: month), notice: "Penalty removed."
      end

      # HR settles part or all of a person's penalty hours with a reason; the rest stays.
      def remove_penalty_hours
        @employee = find_manageable_employee
        minutes = (params[:hours].to_f * 60).round
        reason = params[:reason].to_s.strip
        held = AttendancePenalty.held_minutes(@employee.id)[@employee.id].to_i
        back = admin_attendance_path(@employee.id, anchor: "penalties")
        return redirect_to back, alert: "A reason is required." if reason.blank?
        return redirect_to back, alert: "Remove between 0.5h and #{helpers.hrl_days(held / 60.0)}h." unless minutes.positive? && minutes <= held

        removal = PenaltyRemoval.create!(user_id: @employee.id, minutes: minutes, reason: reason, removed_by_id: hr_current_user.id)
        hours = helpers.hrl_days(minutes / 60.0)
        AuditLog.record!(action: "attendance.penalty_hours_removed", subject: removal, actor: hr_current_user,
                         changes: { "minutes" => minutes, "reason" => reason })
        Notifications.publish("attendance.penalty_removed", title: "HR removed #{hours}h of your penalties", body: reason,
                                                            path: "/attendance#penalties", bell_to: [ @employee ], email_to: [ @employee ])
        redirect_to back, notice: "Removed #{hours}h of penalties."
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
