module HrLite
  module Admin
    # Day-to-day operations: the overview board, team attendance, leave
    # decisions, balance adjustments.
    #
    # The gate is now "can you decide somebody's leave, or fix somebody's
    # attendance" rather than "are you an admin". That is what admits a
    # MANAGER to these screens for the first time — at `team` scope, which
    # every controller below then enforces row by row. Reaching the screen
    # and reaching a particular person's row are two separate questions, and
    # conflating them is precisely the bug this replaces.
    class BaseController < ApplicationController
      before_action :require_operations_access!

      private

      def require_operations_access!
        return if hr_can?("leave.approve", scope: :team) ||
                  hr_can?("attendance.manage", scope: :team) ||
                  hr_can?("leave.view", scope: :team)

        hr_access_denied
      end
    end
  end
end
