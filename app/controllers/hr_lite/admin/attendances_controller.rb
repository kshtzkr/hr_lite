module HrLite
  module Admin
    class AttendancesController < BaseController
      # Team day view: everyone × their punch/status for one date.
      def index
        @date = parse_date_param(params[:date])
        @employees = HrLite.employees
        @records = AttendanceRecord.for_date(@date).where(user_id: @employees.map(&:id)).index_by(&:user_id)
        @flagged_count = @records.values.count(&:flagged?)
      end

      # One employee's month + the regularization form for ?date=.
      def show
        @employee = HrLite.user_klass.find(params[:user_id])
        @month = parse_month_param(params[:month])
        @day_status = DayStatus.new(user: @employee, range: @month.beginning_of_month..@month.end_of_month)
        @counts = @day_status.counts
        @edit_date = params[:date].present? ? parse_date_param(params[:date]) : nil
        @edit_record = @edit_date && AttendanceRecord.find_or_initialize_by(user_id: @employee.id, date: @edit_date)
      end

      # Regularization: fix punches with a mandatory note, fully audited.
      # Clearing both punch times deletes the record (that is how an
      # erroneous punch is removed).
      def update
        @employee = HrLite.user_klass.find(params[:user_id])
        date = parse_date_param(params[:date])
        record = AttendanceRecord.find_or_initialize_by(user_id: @employee.id, date: date)

        note = params.dig(:attendance_record, :regularization_note).to_s.strip
        if note.blank?
          return redirect_to admin_attendance_path(@employee.id, date: date, month: date.strftime("%Y-%m")),
                             alert: "A regularization note is required."
        end

        attrs = params.require(:attendance_record).permit(:check_in_at, :check_out_at, :status)
        if attrs[:check_in_at].blank? && attrs[:check_out_at].blank?
          record.destroy if record.persisted?
          log_regularization(record, note, removed: true)
          return redirect_to admin_attendance_path(@employee.id, month: date.strftime("%Y-%m")),
                             notice: "Punch removed."
        end

        record.assign_attributes(attrs)
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

      def log_regularization(record, note, removed:)
        AuditLog.create!(
          actor: hr_current_user, action: removed ? "destroy" : "regularize",
          subject_type: record.class.name, subject_id: record.id || 0,
          audited_changes: { "date" => record.date.to_s, "note" => note }
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
