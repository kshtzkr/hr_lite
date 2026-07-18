module HrLite
  # All host integration points. Every attribute has a working default so the
  # engine boots in any Rails app; a real host overrides what it needs in an
  # initializer. See README for the full annotated example.
  class Configuration
    attr_accessor :user_class, :parent_controller, :current_user_method,
                  :authenticate_method, :admin_check, :display_name_method,
                  :employees_scope, :mentionable_users, :notify, :render_pdf, :company,
                  :time_zone, :currency_symbol, :on_designation_change,
                  :leadership_emails, :leadership_check, :extra_stylesheets,
                  :mailer_from, :mail_link_base, :notification_matrix, :back_link

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
      @leadership_emails     = []
      @leadership_check      = ->(user) do
        emails = HrLite.config.leadership_emails.map { |e| e.to_s.downcase.strip }
        emails.include?(user.email.to_s.downcase)
      end
      @extra_stylesheets     = [] # host stylesheets linked AFTER hr_lite.css (CSS-var overrides)
      @mailer_from           = "hr@example.com"
      @mail_link_base        = nil # e.g. "https://hr.example.com" — enables email link buttons
      @notification_matrix   = nil # resolved lazily to Notifications::DEFAULT_MATRIX
      @back_link             = nil # optional {label:, url:} for the shell nav
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
