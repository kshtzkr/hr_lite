module HrLite
  module Admin
    # Day-to-day operations tier: overview board, team attendance,
    # leave decisions, balance adjustments. Leadership members are
    # allowed too — governing implies at least operational visibility.
    class BaseController < ApplicationController
      before_action :require_hr_admin!

      private

      def require_hr_admin!
        hr_access_denied unless hr_admin? || hr_leadership?
      end
    end
  end
end
