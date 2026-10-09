module HrLite
  module Admin
    # Employee of the month, quarter and year. Leadership picks the winner.
    class AwardsController < LeadershipController
      before_action :set_award, only: %i[edit update]

      def index
        @awards = paginate(Award.includes(:user).recent_first)
      end

      def new
        @award = Award.new(kind: "month", period_start: Date.current)
      end

      def create
        @award = Award.new(award_params.merge(created_by_id: hr_current_user.id))
        if @award.save
          redirect_to admin_awards_path, notice: "#{@award.title} saved."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @award.update(award_params)
          redirect_to admin_awards_path, notice: "Award updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_award = @award = Award.find(params[:id])

      def award_params
        params.require(:award).permit(:user_id, :kind, :period_start, :citation)
      end
    end
  end
end
