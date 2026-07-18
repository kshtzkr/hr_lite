# hr_lite

A lightweight, self-contained HRMS engine for Rails — attendance with
geolocation, leave management, holiday calendar, full Indian payroll
(PF/ESI/PT/TDS) with salary-slip PDFs, kudos with @mentions, appraisals and
promotions. Think Keka-lite, mounted inside your existing app in a few lines.

- **Mountable engine**, isolated namespace (`HrLite`), tables prefixed `hr_lite_`.
- **Bring your own users**: any user model + auth (Devise or otherwise) via config hooks.
- **Three access tiers**: employee (self-service), admin (day-to-day operations),
  leadership (policy, money, payroll — a configurable email list).
- **Powerful notifications**: one event bus routing every HR event to in-app
  bells (your notifier), employee emails, and leadership emails — with an
  append-only audit trail of every governing change.
- **Self-contained UI**: mobile-first, dependency-free JS, all theming via
  CSS custom properties (`--hrl-*`).
- **Encrypted at rest**: PAN/UAN/bank numbers and every money amount use
  ActiveRecord encryption.

## Installation

```ruby
# Gemfile
gem "hr_lite"
```

```ruby
# config/routes.rb — mount anywhere: a path, or a subdomain
constraints subdomain: "hr" do
  mount HrLite::Engine => "/", as: :hr_lite
end
```

```bash
bin/rails hr_lite:install:migrations db:migrate
bin/rails hr_lite:seed   # default leave types + fixed national holidays (idempotent)
```

Your app must have ActiveRecord encryption keys configured
(`bin/rails db:encryption:init` if you have not).

## Configuration

```ruby
# config/initializers/hr_lite.rb
HrLite.configure do |c|
  c.parent_controller   = "ApplicationController"  # inherits your auth, set BEFORE boot
  c.user_class          = "User"
  c.current_user_method = :current_user
  c.authenticate_method = :authenticate_user!
  c.admin_check         = ->(user) { user.admin? }

  # Leadership: the governing tier. Only these people can change leave
  # policy, offices, holidays, employee profiles, salary structures,
  # payroll, appraisals. Change the list, not the code.
  c.leadership_emails = ENV.fetch("HR_LEADERSHIP_EMAILS", "").split(",").map(&:strip)

  # In-app notifications -> your bell system.
  c.notify = ->(user:, kind:, title:, body:, path:) {
    StaffNotifier.notify(user, kind: kind, title: title, body: body, path: path)
  }

  c.mailer_from    = "hr@example.com"
  c.mail_link_base = "https://hr.example.com"   # enables deep links in emails
  c.company        = -> { { name: "Acme", address: "Head office address", logo_path: nil } }

  # Salary-slip PDFs: plug your renderer, or add wicked_pdf to your bundle
  # and the built-in renderer takes over. Without either, PDF is disabled.
  c.render_pdf = ->(template:, assigns:, cache_key:) {
    PdfRenderer.render(template: template, assigns: assigns, cache_key: cache_key)
  }

  # Mirror promotions into your own user model (optional).
  c.on_designation_change = ->(user, designation) { user.update!(designation: designation) }
end
```

Every event's channels are configurable via `c.notification_matrix` — see
`HrLite::Notifications::DEFAULT_MATRIX` for the routing table (bell /
employee email / leadership email / leadership bell per event).

## Recurring jobs (host scheduler)

| Job | Schedule | Purpose |
|---|---|---|
| `HrLite::DailyDigestJob` | mornings | leadership digest: out today, pending approvals, flagged punches |
| `HrLite::LeaveYearRolloverJob` | Jan 1 | carry-forward balances (idempotent) |

## Theming

Override the CSS variables, nothing else:

```css
:root { --hrl-accent: #00a24f; --hrl-font: "Inter", sans-serif; }
```

All views are also overridable via standard engine view precedence.

## Statutory disclaimer

Payroll math (PF, ESI, PT, TDS) is projection-grade and configured in
`HrLite::StatutoryRateCard` — a date-keyed rate table. **Verify the rates for
each financial year with your accountant** before the first run; per-slip
LOP/TDS overrides are the escape hatch. Surcharge, perquisites and
HRA-exemption math are not modelled.

## Development

```bash
bundle install
bundle exec rspec          # dummy-app test suite (100% line coverage)
COVERAGE=1 bundle exec rspec
bundle exec rubocop
```

## License

MIT.
