# hr_lite — every host integration point in one place.
# Full reference: https://github.com/kshtzkr/hr_lite/blob/main/docs/CONFIGURATION.md
HrLite.configure do |c|
  # Inherit your auth stack. MUST be set before boot; restart after changing.
  c.parent_controller   = "ApplicationController"
  c.user_class          = "User"
  c.current_user_method = :current_user
  c.authenticate_method = :authenticate_user!

  # Access is a role table, not configuration — `rake hr_lite:seed` creates
  # the built-in roles and you assign people from /admin/roles. The first
  # person needs Super Admin, which the upgrade migration grants on an
  # existing install; on a fresh one, from a console:
  #
  #   HrLite::RoleAssignment.create!(
  #     user_id: User.find_by!(email: "you@example.com").id,
  #     role: HrLite::Role.find_by!(name: HrLite::Role::SUPER_ADMIN))
  #
  # Upgrading from pre-0.6.0 and not ready to move? Uncomment this and keep
  # your leadership_emails / superadmin_emails / admin_check as they were.
  # It is honoured until 0.7.0.
  # c.legacy_tier_checks = true

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
