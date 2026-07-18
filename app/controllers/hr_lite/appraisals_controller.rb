module HrLite
  # Employee view: shared appraisals only — drafts do not exist for them.
  class AppraisalsController < ApplicationController
    def index
      @appraisals = paginate(own_shared.recent_first)
    end

    def show
      @appraisal = own_shared.find(params[:id])
    end

    private

    def own_shared
      Appraisal.shared.where(user_id: hr_current_user.id)
    end
  end
end
