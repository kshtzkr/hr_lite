module HrLite
  module Admin
    # Governing screens: policy and people for the whole company — leave
    # types, settings, office locations, holidays, employee profiles,
    # resignations, the audit trail.
    #
    # `profile.manage` at `all` is the key, because governing is exactly the
    # authority to change somebody else's record. Reaching an operations
    # screen is not enough, and neither is managing a team.
    class LeadershipController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_governing_access!

      private

      def require_governing_access!
        hr_require_permission!("profile.manage", scope: :all)
      end
    end
  end
end
