module HrLite
  class KudosController < ApplicationController
    def index
      @kudos = paginate(Kudo.recent.includes(:giver, kudo_mentions: :user))
      @kudo = Kudo.new
    end

    def create
      @kudo = Kudo.new(kudo_params.merge(giver: hr_current_user))
      if @kudo.save
        @kudo.register_mentions!
        redirect_to kudos_path, notice: "Kudos posted."
      else
        @kudos = paginate(Kudo.recent.includes(:giver, kudo_mentions: :user))
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      kudo = Kudo.find(params[:id])
      if kudo.deletable_by?(hr_current_user)
        kudo.destroy!
        redirect_to kudos_path, notice: "Kudos removed.", status: :see_other
      else
        redirect_to kudos_path, alert: "You can only remove your own kudos within 15 minutes.",
                                status: :see_other
      end
    end

    private

    def kudo_params
      params.require(:kudo).permit(:message, :badge)
    end
  end
end
