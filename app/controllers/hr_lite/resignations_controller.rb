module HrLite
  # Employee self-service resignation: submit, see status, withdraw while
  # pending. Always scoped to hr_current_user.
  class ResignationsController < ApplicationController
    def show
      @resignation = own.recent_first.first
      @new_resignation = Resignation.new(proposed_last_day: Date.current + 30) unless @resignation&.pending?
    end

    def create
      @resignation = Resignation.new(resignation_params.merge(user_id: hr_current_user.id))
      if @resignation.save
        redirect_to resignation_path, notice: "Resignation submitted — leadership has been notified."
      else
        @new_resignation = @resignation
        render :show, status: :unprocessable_entity
      end
    end

    def withdraw
      resignation = own.pending.first
      if resignation
        resignation.withdraw!(actor: hr_current_user)
        redirect_to resignation_path, notice: "Resignation withdrawn."
      else
        redirect_to resignation_path, alert: "Nothing pending to withdraw."
      end
    end

    private

    def own
      Resignation.where(user_id: hr_current_user.id)
    end

    def resignation_params
      params.require(:resignation).permit(:reason, :proposed_last_day)
    end
  end
end
