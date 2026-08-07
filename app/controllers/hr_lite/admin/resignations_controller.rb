module HrLite
  module Admin
    class ResignationsController < LeadershipController
      def accept
        resignation = Resignation.find(params[:id])
        resignation.accept!(
          actor: hr_current_user,
          # `.to_date` on a raw param raises Date::Error and 500s; the
          # controller's own parser exists for exactly this.
          last_day: params[:last_day].presence && parse_date_param(params[:last_day]),
          note: params[:note]
        )
        notice = if resignation.exit_date_recorded?
          "Resignation accepted — exit date recorded on the profile."
        else
          "Resignation accepted. No employee profile exists for " \
            "#{hr_display_name(resignation.user)}, so no exit date was recorded — " \
            "create the profile to clip attendance and payroll."
        end
        redirect_to admin_employees_path, notice: notice
      rescue ActiveRecord::RecordInvalid => e
        # A rejected exit date used to be reported as "not pending", which was
        # simply the wrong reason: the transaction rolls back either way.
        message = resignation.reload.pending? ? e.record.errors.full_messages.to_sentence
                                              : "Only pending resignations can be accepted."
        redirect_to admin_employees_path, alert: message
      end
    end
  end
end
