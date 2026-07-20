module HrLite
  module Admin
    # Money tier: salary structures, payroll, slips, appraisals and
    # promotions. Only config.superadmin_emails — ordinary leadership can
    # govern policy and people but never sees another person's pay.
    class SuperadminController < LeadershipController
      before_action :require_hr_superadmin!

      private

      def require_hr_superadmin!
        hr_access_denied unless hr_superadmin?
      end
    end
  end
end
