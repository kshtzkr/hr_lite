module HrLite
  module Admin
    class LeaveBalancesController < BaseController
      def index
        year = params[:year].to_i
        @year = year.between?(2000, 2100) ? year : Date.current.year
        @types = LeaveType.active.where(paid: true).where.not(annual_quota: nil)
        @employees = HrLite.employees
      end

      # Manual credit/debit — also the comp-off credit mechanism.
      def adjust
        user = HrLite.user_klass.find(params[:user_id])
        type = LeaveType.find(params[:leave_type_id])
        year = params[:year].to_i
        delta = BigDecimal(params[:delta].to_s)
        note = params[:note].to_s.strip

        if note.blank?
          return redirect_to admin_leave_balances_path(year: year), alert: "A note is required."
        end

        balance = LeaveBalance.for(user, type, year)
        balance.adjustment += delta
        balance.adjustment_note = [ balance.adjustment_note.presence, "#{delta.to_f} — #{note}" ].compact.join("; ")
        balance.save!

        AuditLog.create!(
          actor: hr_current_user, action: "adjust",
          subject_type: balance.class.name, subject_id: balance.id,
          audited_changes: { "user" => HrLite.display_name(user), "type" => type.code,
                             "delta" => delta.to_f, "note" => note }
        )
        redirect_to admin_leave_balances_path(year: year),
                    notice: "Balance adjusted for #{HrLite.display_name(user)}."
      rescue ArgumentError
        redirect_to admin_leave_balances_path, alert: "Enter a valid adjustment number."
      end
    end
  end
end
