module HrLite
  module Admin
    # Money screens: salary structures, payroll, slips, appraisals and
    # promotions. Ordinary governing authority reaches none of it — leadership
    # governs policy and people but never sees another person's pay.
    #
    # The money gate stands on its own rather than layering on the governing
    # one: a payroll operator does not have to also govern people and policy.
    # Stacking the two locked a configured money-tier user who was absent from
    # the leadership list out of payroll entirely.
    class SuperadminController < LeadershipController
      skip_before_action :require_governing_access!
      before_action :require_money_access!

      private

      # Deliberately payroll.manage rather than a "super admin" role name:
      # roles are data an install re-cuts, and gating on a NAME would make
      # renaming one a silent lock-out.
      def require_money_access!
        hr_require_permission!("payroll.manage", scope: :all)
      end
    end
  end
end
