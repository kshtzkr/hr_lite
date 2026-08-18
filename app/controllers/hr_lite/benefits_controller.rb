module HrLite
  # What the signed-in person is actually covered for — previously something
  # you had to email somebody to find out.
  class BenefitsController < ApplicationController
    before_action :require_viewing!

    def index
      @enrolments = BenefitEnrolment.live_on(Date.current)
                                    .where(user_id: hr_current_user.id)
                                    .includes(:benefit)
    end

    private

    def require_viewing! = hr_require_permission!("benefit.view")
  end
end
