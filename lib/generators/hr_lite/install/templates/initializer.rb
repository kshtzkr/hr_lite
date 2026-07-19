# hr_lite — every host integration point in one place.
# Full reference: https://github.com/kshtzkr/hr_lite/blob/main/docs/CONFIGURATION.md
HrLite.configure do |c|
  # Inherit your auth stack. MUST be set before boot; restart after changing.
  c.parent_controller   = "ApplicationController"
  c.user_class          = "User"
  c.current_user_method = :current_user
  c.authenticate_method = :authenticate_user!

  # Operations tier (team attendance, leave decisions, overview board).
  c.admin_check = ->(user) { user.respond_to?(:admin?) && user.admin? }

  # Governing tier — ONLY these people change policy, employee profiles,
  # salary structures, payroll and appraisals. Keep it in an env var so
  # changing leadership never needs a deploy.
  c.leadership_emails = ENV.fetch("HR_LEADERSHIP_EMAILS", "").split(",").map(&:strip)

  # Where the portal is reachable (subdomain or path). Enables email link
  # buttons and HrLite.public_url / HrLite.public_url? for deep links.
  # c.public_url_base = "https://hr.example.com"

  c.mailer_from = "hr@example.com"
  c.company = -> { { name: "Your Company", address: nil, logo_path: nil } }
  c.time_zone = "Asia/Kolkata"

  # In-app notifications -> your bell/notification system (optional).
  # c.notify = ->(user:, kind:, title:, body:, path:) {
  #   Notifier.notify(user, kind: kind, title: title, body: body,
  #                   path: HrLite.public_url(path))
  # }

  # Salary-slip PDFs: plug your renderer, or add `gem "wicked_pdf"` +
  # wkhtmltopdf and the built-in renderer takes over (optional).
  # c.render_pdf = ->(template:, assigns:, cache_key:) { ... }

  # Mirror promotions into your own user model (optional).
  # c.on_designation_change = ->(user, designation) { user.update!(designation: designation) }

  # Retheme via CSS variables (optional): create a stylesheet overriding
  # --hrl-* vars and list it here.
  # c.extra_stylesheets = [ "hr_lite_overrides" ]

  # Escape hatch back to your app in the HR nav (optional).
  # c.back_link = { label: "Back to app", url: "https://app.example.com" }
end
