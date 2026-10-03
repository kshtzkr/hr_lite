module HrLite
  module Admin
    class OverviewController < BaseController
      SECTION_CAP = 10

      def index
        @query = OverviewQuery.new(user_ids: hr_access.visible_user_ids("leave.view"))
        @kpis = @query.kpis
      end
    end
  end
end
