module HrLite
  # Inherits from the host-configured parent controller (set
  # config.parent_controller in an initializer BEFORE boot; changing it needs
  # a restart). Everything else — auth method, current user, admin/leadership
  # checks — is resolved per request from the live config.
  class ApplicationController < HrLite.config.parent_controller.constantize
    layout "hr_lite/application"

    before_action :hr_authenticate!
    before_action :hr_set_current_actor
    around_action :hr_use_time_zone

    helper_method :hr_current_user, :hr_admin?, :hr_leadership?, :hr_superadmin?, :hr_display_name

    private

    def hr_authenticate!
      send(HrLite.config.authenticate_method)
    end

    def hr_current_user
      send(HrLite.config.current_user_method)
    end

    def hr_admin?
      HrLite.admin?(hr_current_user)
    end

    def hr_superadmin?
      HrLite.superadmin?(hr_current_user)
    end

    def hr_leadership?
      HrLite.leadership?(hr_current_user)
    end

    def hr_display_name(user)
      HrLite.display_name(user)
    end

    def hr_set_current_actor
      HrLite::Current.actor = hr_current_user
    end

    def hr_use_time_zone(&)
      Time.use_zone(HrLite.config.time_zone, &)
    end

    def hr_access_denied
      respond_to do |format|
        format.html { redirect_to hr_lite.root_path, alert: "You do not have access to that area." }
        format.any { head :forbidden }
      end
    end

    # Strict param parsing: anything that isn't the exact expected format
    # falls back to today (never 500s on a mangled URL).
    def parse_month_param(value)
      Date.strptime(value.to_s, "%Y-%m")
    rescue ArgumentError, TypeError
      Date.current.beginning_of_month
    end

    def parse_date_param(value)
      Date.strptime(value.to_s, "%Y-%m-%d")
    rescue ArgumentError, TypeError
      Date.current
    end

    # Minimal LIMIT/OFFSET pagination — no host dependency.
    def paginate(scope, per: 25)
      @per = [ [ params.fetch(:per, per).to_i, 1 ].max, 100 ].min
      @page = [ params.fetch(:page, 1).to_i, 1 ].max
      @total_count = scope.count
      @total_pages = [ (@total_count.to_f / @per).ceil, 1 ].max
      @page = @total_pages if @page > @total_pages
      scope.offset((@page - 1) * @per).limit(@per)
    end
  end
end
