module HrLite
  module Admin
    class ResignationsController < LeadershipController
      def accept
        resignation = Resignation.find(params[:id])
        resignation.accept!(
          actor: hr_current_user,
          last_day: params[:last_day].presence&.to_date,
          note: params[:note]
        )
        redirect_to admin_employees_path,
                    notice: "Resignation accepted — exit date recorded on the profile."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_employees_path, alert: "Only pending resignations can be accepted."
      end
    end
  end
end
