module HrLite
  class CareerController < ApplicationController
    def show
      @profile = EmployeeProfile.find_by(user_id: hr_current_user.id)
      @changes = DesignationChange.where(user_id: hr_current_user.id).timeline
      @appraisals = Appraisal.shared.where(user_id: hr_current_user.id).recent_first.limit(10)
    end
  end
end
