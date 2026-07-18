module HrLite
  module Admin
    class SalarySlipsController < LeadershipController
      def show
        @slip = SalarySlip.includes(:payroll_run).find(params[:id])
        @profile = @slip.user_profile
      end

      # Review-stage overrides (LOP days / monthly TDS) — the slip rebuilds
      # immediately with the overrides applied.
      def update
        slip = SalarySlip.includes(:payroll_run).find(params[:id])
        run = slip.payroll_run
        unless run.review?
          return redirect_to admin_salary_slip_path(slip),
                             alert: "Overrides are only editable while the run is in review."
        end

        lop_override = params.dig(:salary_slip, :lop_override).presence
        tds_override = params.dig(:salary_slip, :tds_override).presence
        profile = EmployeeProfile.find_by(user_id: slip.user_id)
        structure = SalaryStructure.effective_for(slip.user, run.period_month)

        attributes = SlipBuilder.call(
          run: run, user: slip.user, structure: structure, profile: profile,
          lop_override: lop_override && BigDecimal(lop_override),
          tds_override: tds_override && BigDecimal(tds_override)
        )
        slip.update!(attributes)

        AuditLog.create!(
          actor: hr_current_user, action: "override",
          subject_type: slip.class.name, subject_id: slip.id,
          audited_changes: { "period" => run.label, "employee" => HrLite.display_name(slip.user),
                             "lop_override" => lop_override || "cleared",
                             "tds_override" => tds_override ? "[changed]" : "cleared" }
        )
        redirect_to admin_salary_slip_path(slip), notice: "Slip recomputed with overrides."
      rescue ArgumentError
        redirect_to admin_salary_slip_path(params[:id]), alert: "Overrides must be numbers."
      end
    end
  end
end
