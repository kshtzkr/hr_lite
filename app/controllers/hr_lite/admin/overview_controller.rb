module HrLite
  module Admin
    class OverviewController < BaseController
      SECTION_CAP = 10

      def index
        @query = OverviewQuery.new
        @kpis = @query.kpis
      end
    end
  end
end
