require "hr_lite/version"
require "hr_lite/engine"
require "hr_lite/configuration"
require "hr_lite/current"
require "hr_lite/leave_year"
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

    def admin?(user)
      user.present? && !!config.admin_check.call(user)
    end

    def leadership?(user)
      user.present? && !!config.leadership_check.call(user)
    end

    # Leadership members resolvable to actual user records (for bell
    # notifications). Emails configured but absent from the user table are
    # still reachable by email — see Notifications.
    def leadership_users
      emails = config.leadership_emails.map { |e| e.to_s.downcase.strip }.reject(&:empty?)
      return user_klass.none if emails.empty?

      user_klass.where("LOWER(#{user_klass.table_name}.email) IN (?)", emails)
    end

    def admin_users
      user_klass.all.select { |u| admin?(u) }
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
