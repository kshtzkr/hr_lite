module HrLite
  module Admin
    class LeaveBalancesController < BaseController
      def index
        @year = sanitized_year
        @types = LeaveType.active.where(paid: true).where.not(annual_quota: nil)
        @employees = HrLite.employees
      end

      # Manual credit/debit — also the comp-off credit mechanism.
      def adjust
        user = HrLite.user_klass.find(params[:user_id])
        type = LeaveType.find(params[:leave_type_id])
        # Unsanitised, a missing param wrote the adjustment into leave year 0,
        # where no screen can ever show it.
        year = sanitized_year
        delta = BigDecimal(params[:delta].to_s)
        note = params[:note].to_s.strip

        if note.blank?
          return redirect_to admin_leave_balances_path(year: year), alert: "A note is required."
        end

        balance = LeaveBalance.adjust!(user, type, year, delta: delta, note: "#{delta.to_f} — #{note}")

        AuditLog.create!(
          actor: hr_current_user, action: "adjust",
          subject_type: balance.class.name, subject_id: balance.id,
          audited_changes: { "user" => HrLite.display_name(user), "type" => type.code,
                             "delta" => delta.to_f, "note" => note }
        )
        redirect_to admin_leave_balances_path(year: year),
                    notice: "Balance adjusted for #{HrLite.display_name(user)}."
      rescue ArgumentError
        # Keep the admin on the year they were looking at.
        redirect_to admin_leave_balances_path(year: sanitized_year),
                    alert: "Enter a valid adjustment number."
      end

      private

      def sanitized_year
        year = params[:year].to_i
        year.between?(2000, 2100) ? year : LeaveYear.current_key
      end
    end
  end
end
