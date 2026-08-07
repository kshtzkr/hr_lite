module HrLite
  module Admin
    # Money tier: salary structures, payroll, slips, appraisals and
    # promotions. Only config.superadmin_emails — ordinary leadership can
    # govern policy and people but never sees another person's pay.
    # The money tier stands on its own rather than layering on leadership: a
    # payroll operator does not have to also govern people and policy.
    # Inheriting the leadership check locked a configured superadmin who was
    # absent from leadership_emails out of payroll entirely.
    class SuperadminController < LeadershipController
      skip_before_action :require_hr_leadership!
      before_action :require_hr_superadmin!

      private

      def require_hr_superadmin!
        hr_access_denied unless hr_superadmin?
      end
    end
  end
end
