module HrLite
  module Admin
    # Governing tier: anything that changes policy or money — leave types,
    # settings, office locations, holidays, employee profiles, salary
    # structures, payroll, appraisals, audit trail. Leadership ONLY;
    # being a host-app admin is not enough.
    class LeadershipController < BaseController
      skip_before_action :require_hr_admin!
      before_action :require_hr_leadership!

      private

      def require_hr_leadership!
        hr_access_denied unless hr_leadership?
      end
    end
  end
end
