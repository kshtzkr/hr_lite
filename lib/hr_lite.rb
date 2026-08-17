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

    # --- legacy tier predicates --------------------------------------------
    #
    # Kept because views, hosts and the notification fan-out all call them.
    # They are now READ OFF ROLES rather than off a mutable email column; the
    # configured lambdas survive only as an explicit opt-in for a host that
    # has not migrated yet (see Configuration#legacy_tier_checks).

    def admin?(user)
      return false if user.blank?
      return !!config.admin_check.call(user) if config.legacy_tier_checks

      can?(user, "leave.approve", scope: :all) || can?(user, "attendance.manage", scope: :all)
    end

    def leadership?(user)
      return false if user.blank?
      return !!config.leadership_check.call(user) if config.legacy_tier_checks

      can?(user, "profile.manage", scope: :all)
    end

    def superadmin?(user)
      return false if user.blank?
      return !!config.superadmin_check.call(user) if config.legacy_tier_checks

      can?(user, "payroll.manage", scope: :all)
    end

    # An access list, cleaned. "a@x.com,,b@x.com".split(",") — one stray
    # comma in an ENV var — used to put "" in the list, and a user whose
    # email was blank then MATCHED it and was handed the tier.
    def normalize_email_list(emails)
      Array(emails).map { |e| e.to_s.downcase.strip }.reject(&:empty?)
    end

    # Whether a user's own email is on a configured access list. A blank
    # email is never on any list, however the list is spelled.
    def email_listed?(user, emails)
      address = user.respond_to?(:email) ? user.email.to_s.downcase.strip : ""
      return false if address.empty?

      normalize_email_list(emails).include?(address)
    end

    # Leadership members resolvable to actual user records (for bell
    # notifications). On a legacy host, emails configured but absent from the
    # user table are still reachable by email — see Notifications.
    def leadership_users
      unless config.legacy_tier_checks
        return users_holding("profile.manage", scope: :all)
      end

      emails = normalize_email_list(config.leadership_emails)
      return user_klass.none if emails.empty?

      user_klass.where("LOWER(#{user_klass.table_name}.email) IN (?)", emails)
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

    # Every domain event that bells the admins calls this. On roles it is one
    # query over the grant tables; on a legacy host it still has to run the
    # host's lambda per row, which is why it starts from employees_scope
    # (narrowed to real staff) rather than every row that exists.
    def admin_users
      return employees.select { |u| admin?(u) } if config.legacy_tier_checks

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
