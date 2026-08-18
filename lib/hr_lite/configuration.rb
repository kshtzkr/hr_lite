module HrLite
  # All host integration points. Every attribute has a working default so the
  # engine boots in any Rails app; a real host overrides what it needs in an
  # initializer. See README for the full annotated example.
  class Configuration
    attr_accessor :user_class, :parent_controller, :current_user_method,
                  :authenticate_method, :admin_check, :display_name_method,
                  :employees_scope, :mentionable_users, :notify, :render_pdf, :company,
                  :time_zone, :currency_symbol, :on_designation_change,
                  :leadership_emails, :extra_stylesheets, :superadmin_emails,
                  :mailer_from, :public_url_base, :notification_matrix, :back_link,
                  :onboard_user, :offboard_user, :invite_url_for

    attr_reader :leave_year_start_month

    # Misconfiguration must fail at boot, not as production 500s on every
    # balance screen. Accepts "7" (ENV-friendly) and validates 1..12.
    # Changing this on an install with EXISTING balance rows reinterprets
    # them — set it once at install time (see docs/CONFIGURATION.md).
    def leave_year_start_month=(value)
      month = Integer(value)
      raise ArgumentError, "leave_year_start_month must be 1..12, got #{value.inspect}" unless (1..12).cover?(month)

      @leave_year_start_month = month
    end

    # 0.1.0 pre-release name for public_url_base; kept as an alias so early
    # adopters' initializers don't break.
    alias_method :mail_link_base, :public_url_base
    alias_method :mail_link_base=, :public_url_base=

    def initialize
      @user_class            = "User"
      @parent_controller     = "ActionController::Base"
      @current_user_method   = :current_user
      @authenticate_method   = :authenticate_user!
      @admin_check           = ->(user) { user.respond_to?(:admin?) && user.admin? }
      @display_name_method   = :display_name
      @employees_scope       = -> { HrLite.user_klass.all }
      @mentionable_users     = ->(query) { HrLite.default_mentionable_users(query) }
      @notify                = ->(user:, kind:, title:, body:, path:) { }
      @render_pdf            = nil
      @company               = -> { { name: "Company", address: nil, logo_path: nil } }
      @time_zone             = "Asia/Kolkata"
      @currency_symbol      = "₹"
      @on_designation_change = ->(user, designation) { }
      # --- pre-0.6.0 access, now MIGRATION INPUT ONLY ------------------------
      #
      # These three governed access until 0.6.0, and two of them matched the
      # user's EMAIL — a mutable, host-owned, unverified column that every
      # host then had to remember never to let anybody edit. They decide
      # nothing now: `HrLite.admin?` and friends read roles.
      #
      # They are still read in exactly one place — the 0.6.0 upgrade
      # migration, which derives role assignments from whatever a 0.5.x host
      # had configured. An install upgrading across several versions at once
      # needs them present for that migration to have anything to read, which
      # is why they were not deleted outright.
      @leadership_emails     = []
      @superadmin_emails     = []
      @extra_stylesheets     = [] # host stylesheets linked AFTER hr_lite.css (CSS-var overrides)
      @mailer_from           = "hr@example.com"
      @public_url_base       = nil # e.g. "https://hr.example.com" — enables email links + HrLite.public_url
      @notification_matrix   = nil # resolved lazily to Notifications::DEFAULT_MATRIX
      @back_link             = nil # optional {label:, url:} for the shell nav
      @leave_year_start_month = 1  # 1 = calendar year; 7 = July–June leave year

      # Leadership onboarding/offboarding. onboard_user must return a saved
      # user record (default: create on user_class with whatever of
      # name/email/password it supports). offboard_user should revoke the
      # person's access — the engine never deletes anything (statutory
      # records), it only stamps the exit date.
      @onboard_user = ->(name:, email:, password:) {
        klass = HrLite.user_klass
        attributes = { email: email }
        attributes[:name] = name if klass.column_names.include?("name")
        if klass.method_defined?(:password=)
          attributes[:password] = password
          attributes[:password_confirmation] = password if klass.method_defined?(:password_confirmation=)
        end
        klass.create!(attributes)
      }
      @offboard_user = ->(user) { }
      # Optional: return an absolute set-your-password URL for a freshly
      # onboarded user (e.g. a Devise reset link). When present, the welcome
      # email carries it and leadership never needs to hand over a password.
      @invite_url_for = nil
    end
  end

  class << self
    # Default @mention source: name/email prefix match on the host user table.
    # Uses LOWER(...) LIKE so it works on sqlite and postgres alike; hosts
    # with pg_trgm or scopes of their own override config.mentionable_users.
    def default_mentionable_users(query)
      q = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.downcase)}%"
      klass = user_klass
      columns = %w[name email].select { |c| klass.column_names.include?(c) }
      return klass.none if columns.empty?

      where_sql = columns.map { |c| "LOWER(#{klass.table_name}.#{c}) LIKE :q" }.join(" OR ")
      klass.where(where_sql, q: q).order(:id).limit(8)
    end
  end
end
