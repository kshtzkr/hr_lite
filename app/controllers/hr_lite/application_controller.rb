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

    helper_method :hr_current_user, :hr_admin?, :hr_leadership?, :hr_superadmin?, :hr_display_name,
                  :hr_can?, :hr_reaches?, :hr_access

    private

    # --- authorization -----------------------------------------------------

    def hr_access
      HrLite::Access.for(hr_current_user)
    end

    # May the signed-in person do this at all, at `scope` or wider?
    def hr_can?(key, scope: :self)
      hr_access.can?(key, scope: scope)
    end

    # May they do it to THIS person's records? The question the module could
    # not ask before roles, and whose absence let any admin approve anybody's
    # leave.
    def hr_reaches?(key, subject_user)
      hr_access.reaches?(key, subject_user)
    end

    # Gate a whole controller or action. `scope` is the weakest scope that can
    # reach the screen at all — a manager reaching a team screen still has
    # every ROW checked separately by `hr_require_reach!`.
    def hr_require_permission!(key, scope: :self)
      hr_access_denied unless hr_can?(key, scope: scope)
    end

    # Gate one record. Deliberately a 404, not a 403: whether a particular
    # person exists is not something a stranger gets to learn from us.
    def hr_require_reach!(key, subject_user)
      raise ActiveRecord::RecordNotFound unless hr_reaches?(key, subject_user)
    end

    # Narrow a relation to the rows this permission reaches, so an index
    # never renders a row the member action would refuse.
    def hr_scope(relation, key, column: :user_id)
      hr_access.scope_relation(relation, key, column: column)
    end

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
