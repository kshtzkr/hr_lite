module HrLite
  # Read-only masked view of one's own HR profile; edits go through
  # leadership.
  class EmployeeProfilesController < ApplicationController
    def show
      @profile = EmployeeProfile.find_by(user_id: hr_current_user.id)
    end
  end
end
