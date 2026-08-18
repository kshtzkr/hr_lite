require "hr_lite/version"
require "hr_lite/engine"
require "hr_lite/configuration"
require "hr_lite/current"
require "hr_lite/leave_year"
require "hr_lite/financial_year"
require "hr_lite/permissions"
require "hr_lite/role_seeds"
require "hr_lite/statutory_seeds"
require "hr_lite/mention_parser"
require "hr_lite/notifications"
require "hr_lite/seeds"
require "hr_lite/geo"
require "hr_lite/money"
require "hr_lite/amount_in_words"
require "hr_lite/statutory_rate_card"

module HrLite
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    # Test-only escape hatch: swap the whole configuration object.
    def config=(configuration)
      @config = configuration
    end

    def user_klass
      config.user_class.constantize
    end

    # --- authorization -----------------------------------------------------

    # The question every gate now asks. `scope:` is what the CALLER needs;
    # a holder with a wider scope satisfies it.
    def can?(user, key, scope: :self)
      Access.for(user).can?(key, scope: scope)
    end

    # Whether `user` may exercise `key` over `subject`'s rows. This is the
    # question that did not exist before roles, and its absence is why any
    # admin could approve anybody's leave.
    def reaches?(user, key, subject)
      Access.for(user).reaches?(key, subject)
    end

    def access_for(user) = Access.for(user)

    # --- tier predicates ----------------------------------------------------
    #
    # Shorthands over the permissions, kept because views, hosts and the
    # notification fan-out all read better asking "is this person leadership"
    # than "do they hold profile.manage at all scope". They are ROLES all the
    # way down; the pre-0.6.0 lambdas no longer decide anything.

    def admin?(user)
      return false if user.blank?

      can?(user, "leave.approve", scope: :all) || can?(user, "attendance.manage", scope: :all)
    end

    def leadership?(user)
      return false if user.blank?

      can?(user, "profile.manage", scope: :all)
    end

    def superadmin?(user)
      return false if user.blank?

      can?(user, "payroll.manage", scope: :all)
    end

    # An access list, cleaned — read now only by the 0.6.0 upgrade migration.
    # One stray comma in an ENV var ("a@x.com,,b@x.com") used to put "" in the
    # list, and a user whose email was blank then MATCHED it and was handed
    # the tier. Kept honest here so the migration cannot repeat that.
    def normalize_email_list(emails)
      Array(emails).map { |e| e.to_s.downcase.strip }.reject(&:empty?)
    end

    # Leadership members resolvable to actual user records (for bell
    # notifications).
    def leadership_users
      users_holding("profile.manage", scope: :all)
    end

    # Everyone whose roles grant `key` at `scope` or wider. One query over
    # the grant tables rather than instantiating every user and asking.
    def users_holding(key, scope: :all)
      wide = Permissions::SCOPE_RANK.select { |_, rank| rank >= Permissions::SCOPE_RANK.fetch(scope) }
      ids = RoleAssignment.joins(role: :role_grants)
                          .where(hr_lite_role_grants: {
                            permission_key: Permissions.validate!(key), scope: wide.keys.map(&:to_s)
                          })
                          .distinct.pluck(:user_id)
      user_klass.where(id: ids)
    end

    # Every domain event that bells the admins calls this. One query over the
    # grant tables — it used to instantiate every employee and ask each one.
    def admin_users
      users_holding("leave.approve", scope: :all).sort_by { |u| display_name(u).downcase }
    end

    # Everyone HR tracks (host-overridable to exclude bots/test accounts),
    # sorted by display name for team screens.
    def employees
      config.employees_scope.call.sort_by { |u| display_name(u).downcase }
    end

    # employees minus anyone whose profile says they have exited — user
    # accounts outlive employment (slip access), broadcasts must not.
    def active_employees(on: Date.current)
      exits = HrLite::EmployeeProfile.where.not(date_of_exit: nil).pluck(:user_id, :date_of_exit).to_h
      employees.select { |u| exits[u.id].nil? || exits[u.id] >= on }
    end

    def display_name(user)
      return "" if user.nil?

      [ config.display_name_method, :display_name, :name, :email ].each do |m|
        next unless m && user.respond_to?(m)
        value = user.public_send(m).presence
        return value if value
      end
      "User ##{user.id}"
    end

    # Absolute public URL for an engine-relative path, from
    # config.public_url_base. Nil when no base is configured — callers (and
    # emails) then simply carry no link. Hosts use this to build bell
    # deep-links and profile links without re-deriving the HR host.
    def public_url(path = "/")
      base = config.public_url_base.to_s.chomp("/")
      return nil if base.empty?

      "#{base}#{path}"
    end

    # True when the given absolute URL points at the configured public HR
    # host — the allowlist check for hosts that follow stored notification
    # links (an open-redirect guard stays intact on their side).
    def public_url?(candidate)
      base = public_url
      return false if base.nil?

      candidate_uri = URI.parse(candidate.to_s)
      base_uri = URI.parse(base)
      %w[http https].include?(candidate_uri.scheme) && candidate_uri.host == base_uri.host
    rescue URI::InvalidURIError
      false
    end

    # Host bell hook. Never raises — a notification must not break the
    # domain action that triggered it.
    def notify(user:, kind:, title:, body: nil, path: nil)
      config.notify.call(user: user, kind: kind, title: title, body: body, path: path)
    rescue => e
      Rails.logger.error("[hr_lite] notify failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
