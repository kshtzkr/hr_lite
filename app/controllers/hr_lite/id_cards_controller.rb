module HrLite
  # The employee ID card: your own, or — for HR printing it — anyone your
  # `profile.view` reaches. The photo is the one thing an employee edits.
  class IdCardsController < ApplicationController
    def show
      @user = params[:user_id] ? HrLite.user_klass.find(params[:user_id]) : hr_current_user
      hr_require_reach!("profile.view", @user) unless @user == hr_current_user
      @profile = EmployeeProfile.find_by(user_id: @user.id)
      card_requests = HrRequest.where(user_id: @user.id, category: "id_card")
      @issued_on = card_requests.where(status: "resolved").maximum(:resolved_at)
      @print_requested = card_requests.open_requests.pick(:created_at)
    end

    def photo
      profile = EmployeeProfile.find_by!(user_id: hr_current_user.id)
      profile.photo = params.require(:photo)
      if profile.save
        AuditLog.record!(action: "id_card.photo_changed", subject: profile, actor: hr_current_user)
        redirect_to id_card_path, notice: "Photo updated.", status: :see_other
      else
        redirect_to id_card_path, alert: profile.errors.full_messages.to_sentence, status: :see_other
      end
    end
  end
end
