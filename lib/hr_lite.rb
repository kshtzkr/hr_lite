require "hr_lite/version"
require "hr_lite/engine"
require "hr_lite/configuration"
require "hr_lite/current"
require "hr_lite/mention_parser"
require "hr_lite/notifications"
require "hr_lite/seeds"
require "hr_lite/geo"

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

    def display_name(user)
      return "" if user.nil?

      [ config.display_name_method, :display_name, :name, :email ].each do |m|
        next unless m && user.respond_to?(m)
        value = user.public_send(m).presence
        return value if value
      end
      "User ##{user.id}"
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
