# hr_lite

[![CI](https://github.com/kshtzkr/hr_lite/actions/workflows/ci.yml/badge.svg)](https://github.com/kshtzkr/hr_lite/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/hr_lite.svg)](https://rubygems.org/gems/hr_lite)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](MIT-LICENSE)

A lightweight, self-contained HRMS engine for Rails — attendance with
geolocation, leave management with comp-off requests, regularization tickets,
an everyone-visible team board, holiday calendar, full Indian payroll
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

## Try it in one command

```bash
git clone https://github.com/kshtzkr/hr_lite && cd hr_lite
bin/demo    # → http://localhost:3999
```

A throwaway sandbox boots with three persona tiers (leadership / admin /
employee — one click to sign in as each) and pre-seeded attendance, leaves,
kudos, a published payroll run and a shared appraisal. Data resets on every
restart.

## Installation

Everything lives in the gem — a host app adds the gem, a mount line and one
initializer. Nothing else.

```ruby
# Gemfile
gem "hr_lite"
```

```bash
bin/rails g hr_lite:install          # annotated initializer + next steps
bin/rails g hr_lite:install --route  # …and mount at /hr for you
bin/rails db:migrate                 # engine migrations load straight from the gem
bin/rails hr_lite:seed               # leave types + fixed national holidays (idempotent)
```

Migrations are served from the gem (upgrades included) — nothing is copied
into your repo. If you prefer copies, run `bin/rails hr_lite:install:migrations`
once and the engine steps aside.

To serve it on a subdomain instead of a path:

```ruby
# config/routes.rb
constraints subdomain: "hr" do
  mount HrLite::Engine => "/", as: :hr_lite
end
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

## Docs

- [docs/CONFIGURATION.md](docs/CONFIGURATION.md) — every config key, the event
  list and the notification matrix, how the three access tiers gate.
- [docs/PAYROLL.md](docs/PAYROLL.md) — the exact payroll math, rounding rules,
  run lifecycle, and what is deliberately not modelled.

## Statutory disclaimer

Payroll math (PF, ESI, PT, TDS) is projection-grade and configured in
`HrLite::StatutoryRateCard` — a date-keyed rate table. **Verify the rates for
each financial year with your accountant** before the first run; per-slip
LOP/TDS overrides are the escape hatch. Surcharge, perquisites and
HRA-exemption math are not modelled.

## Requirements & versioning

- Rails >= 8.0, Ruby >= 3.2, any ActiveRecord database (portable column
  types; developed against PostgreSQL, CI runs SQLite).
- The host app must have ActiveRecord encryption keys configured.
- [SemVer](https://semver.org): 0.x minors may break with a CHANGELOG note;
  from 1.0, breaking changes only in majors.

## Documentation

- [docs/CONFIGURATION.md](docs/CONFIGURATION.md) — every config hook, the
  event/notification matrix, access-tier gating.
- [docs/PAYROLL.md](docs/PAYROLL.md) — exact payroll math, rounding rules,
  and what is deliberately not modelled.
- [CHANGELOG.md](CHANGELOG.md) — release history.

## Contributing

Bug reports and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for setup and ground rules (100%
coverage, BigDecimal money, config hooks over host couplings). Security
issues: report privately per [SECURITY.md](SECURITY.md). Everyone
interacting with this project is expected to follow the
[code of conduct](CODE_OF_CONDUCT.md).

## Development

```bash
bundle install
bundle exec rspec          # dummy-app test suite (100% line coverage)
COVERAGE=1 bundle exec rspec
bundle exec rubocop
```

## License

The gem is available as open source under the terms of the
[MIT License](MIT-LICENSE).
