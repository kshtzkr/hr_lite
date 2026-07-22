# hr_lite

[![Gem Version](https://img.shields.io/gem/v/hr_lite.svg)](https://rubygems.org/gems/hr_lite)
[![CI](https://github.com/kshtzkr/hr_lite/actions/workflows/ci.yml/badge.svg)](https://github.com/kshtzkr/hr_lite/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-CC342D.svg)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](MIT-LICENSE)

A mountable Rails engine that adds a small HRMS to an app you already have:
attendance with geolocation, leave and holidays, Indian payroll (PF/ESI/PT/TDS)
with salary-slip PDFs, kudos with @mentions, appraisals and promotions. It
brings its own models, controllers and views under the `HrLite` namespace and
talks to your app through configuration hooks — you keep your users and your
auth, it does the HR.

- Mountable engine, isolated namespace (`HrLite`), tables prefixed `hr_lite_`.
- Bring your own users: any user model and auth (Devise or otherwise) via config hooks.
- Access tiers: employee (self-service), admin (day-to-day operations),
  leadership (policy and people), and an optional superadmin tier for money.
- One event bus routes every HR event to in-app bells, employee emails and a
  leadership fan-out, with an append-only audit trail of governing changes.
- Self-contained UI: mobile-first, dependency-free JS, theming through CSS
  custom properties (`--hrl-*`).
- PAN/UAN/bank numbers and every money amount use ActiveRecord encryption.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start (sandbox)](#quick-start-sandbox)
- [Configuration](#configuration)
- [Access tiers](#access-tiers)
- [Features](#features)
  - [Attendance and geolocation](#attendance-and-geolocation)
  - [Leave, comp-off and regularization](#leave-comp-off-and-regularization)
  - [Holidays and calendar](#holidays-and-calendar)
  - [Payroll and salary slips](#payroll-and-salary-slips)
  - [Kudos and @mentions](#kudos-and-mentions)
  - [Notifications and the event bus](#notifications-and-the-event-bus)
  - [Appraisals, promotions and the org chart](#appraisals-promotions-and-the-org-chart)
- [Recurring jobs](#recurring-jobs)
- [Rake tasks](#rake-tasks)
- [Generators](#generators)
- [Theming](#theming)
- [Statutory disclaimer](#statutory-disclaimer)
- [Testing and development](#testing-and-development)
- [Versioning](#versioning)
- [Contributing](#contributing)
- [Documentation](#documentation)
- [License](#license)

## Requirements

- Ruby >= 3.2.
- Rails >= 8.0.
- Any ActiveRecord database. The migrations use portable column types; the gem
  is developed against PostgreSQL and CI runs on SQLite.
- ActiveRecord encryption keys configured in the host app — money amounts and
  identity PII (PAN, UAN, bank details) are encrypted at rest. Run
  `bin/rails db:encryption:init` if you have not set keys up yet.

## Installation

Add the gem to the host app:

```ruby
# Gemfile
gem "hr_lite"
```

```bash
bundle install
bin/rails g hr_lite:install          # writes the annotated initializer, prints next steps
bin/rails g hr_lite:install --route  # …and mounts the engine at /hr for you
bin/rails db:migrate                 # engine migrations load straight from the gem
bin/rails hr_lite:seed               # default leave types + fixed national holidays (idempotent)
```

Migrations ship from the gem — `bin/rails db:migrate` picks them up and upgrades
bring their own migrations, so nothing is copied into your repo and nothing
drifts. If you prefer copies you can manage, run
`bin/rails hr_lite:install:migrations` once; the engine detects the copied
files (`*.hr_lite.rb`) and stops appending its own.

If you did not pass `--route`, mount it yourself:

```ruby
# config/routes.rb — at a path…
mount HrLite::Engine => "/hr", as: :hr_lite

# …or on a subdomain:
constraints subdomain: "hr" do
  mount HrLite::Engine => "/", as: :hr_lite
end
```

## Quick start (sandbox)

```bash
git clone https://github.com/kshtzkr/hr_lite && cd hr_lite
bin/demo    # boots a throwaway app on http://localhost:3999
```

The sandbox boots a fresh SQLite database with sample data across three persona
tiers (leadership, admin, employee — one click to sign in as each) and
pre-seeded attendance, leaves, kudos, a published payroll run and a shared
appraisal. The data resets on every restart.

## Configuration

`bin/rails g hr_lite:install` writes `config/initializers/hr_lite.rb`. Every
key has a working default, so the engine boots in any app; override what your
app needs:

```ruby
# config/initializers/hr_lite.rb
HrLite.configure do |c|
  c.parent_controller   = "ApplicationController"  # inherit your auth; resolved once at boot
  c.user_class          = "User"
  c.current_user_method = :current_user
  c.authenticate_method = :authenticate_user!
  c.admin_check         = ->(user) { user.respond_to?(:admin?) && user.admin? }

  # The governing tier: only these people change leave policy, offices,
  # holidays, employee profiles, salary structures, payroll and appraisals.
  c.leadership_emails = ENV.fetch("HR_LEADERSHIP_EMAILS", "").split(",").map(&:strip)

  # In-app notifications -> your bell system (optional; a no-op by default).
  c.notify = ->(user:, kind:, title:, body:, path:) {
    StaffNotifier.notify(user, kind: kind, title: title, body: body, path: path)
  }

  c.mailer_from     = "hr@example.com"
  c.public_url_base = "https://hr.example.com"  # enables deep links in emails
  c.company         = -> { { name: "Acme", address: "Head office address", logo_path: nil } }

  # Salary-slip PDFs: plug your renderer, or add wicked_pdf to the bundle and
  # the built-in renderer takes over. With neither, PDF export is disabled.
  c.render_pdf = ->(template:, assigns:, cache_key:) {
    PdfRenderer.render(template: template, assigns: assigns, cache_key: cache_key)
  }

  # Mirror promotions into your own user model (optional).
  c.on_designation_change = ->(user, designation) { user.update!(designation: designation) }
end
```

`docs/CONFIGURATION.md` documents every key with its type, default and when to
override it, plus the full event/notification matrix. `parent_controller` is
resolved once at boot — restart after changing it.

## Access tiers

Authorization is layered on top of the checks you provide. There is no separate
role table; a user's tier is derived per request.

- **Employee** — every signed-in user. All self-service screens are scoped to
  `current_user` (asking for someone else's record 404s), so a new hire is
  never locked out.
- **Admin** (`admin_check`, or anyone in leadership) — day-to-day operations:
  team attendance, leave and regularization decisions, the overview board.
- **Leadership** (`leadership_check` only — admin is not enough) — policy and
  people: leave types, offices, holidays, the weekend rule, employee profiles,
  onboarding/offboarding, the audit trail. Every leadership mutation writes an
  append-only `hr_lite_audit_logs` row and emails leadership with the diff.
- **Superadmin (money)** (`superadmin_check`) — salary structures, payroll
  runs, salary-slip administration, appraisals and promotions. Set
  `superadmin_emails` to a subset of leadership to separate money from policy.
  Left empty (the default), the money tier is the leadership tier.

Leadership is a list you control, not code. The generated initializer reads it
from `HR_LEADERSHIP_EMAILS` (a comma-separated list) so you can change who
governs without a deploy — that env var is a convention in the initializer the
generator writes, not something the gem reads on its own. You can drop the env
var and assign `c.leadership_emails` directly, or replace `c.leadership_check`
to derive leadership some other way.

`HrLite.admin?(user)`, `HrLite.leadership?(user)` and `HrLite.superadmin?(user)`
are available if you need the same checks in host code.

## Features

Once mounted, staff use the portal at the mount point; admins and leadership get
an `/admin` area. The routes below are relative to the mount path.

### Attendance and geolocation

Employees check in and out from `/attendance` (`POST check_in` / `check_out`).
The browser sends latitude, longitude and accuracy with each punch. Geolocation
never blocks a punch: a punch with no GPS, or one outside every office radius,
is still recorded and then flagged for review — denying location access must not
stop anyone from working. Distance is a pure-Ruby haversine, so there is no
geocoding dependency:

```ruby
HrLite::Geo.distance_m(office.lat, office.lng, punch_lat, punch_lng) # => metres
```

Offices are `HrLite::OfficeLocation` records with a `radius_m`; leadership
manages them under `/admin/office_locations`. `OfficeLocation.covering?(lat,
lng)` answers whether a point falls inside any active office, and
`OfficeLocation.nearest(lat, lng)` backs the flag note ("1.2 km from Head
Office"). Admins see the team's day and flagged punches under
`/admin/attendances`.

### Leave, comp-off and regularization

Leave types are policy rows (`HrLite::LeaveType`) with quota, accrual
(`monthly` or `yearly_upfront`), carry-forward cap and paid/unpaid flag; seeds
create a sensible default set (CL, SL, EL, LWP, CO). Balances are computed
against a leave year whose start month is configurable:

```ruby
HrLite.configure { |c| c.leave_year_start_month = 7 } # July–June instead of Jan–Dec
HrLite::LeaveYear.current_key   # => 2026
HrLite::LeaveYear.label(2026)   # => "2026–27"
```

Set `leave_year_start_month` once, at install time — balance rows are keyed by
leave year, and changing it later reinterprets stored balances. Entitlement
prorates from the joining date (joined on or before the 15th counts that month).

Employees apply, cancel and track balances at `/leave_requests` and
`/leave_balances`; admins approve or reject under `/admin/leave_requests`.
Comp-off requests (`/comp_off_requests`) credit the comp-off leave type when
approved; regularization tickets (`/regularization_requests`) let someone who
forgot to punch propose the real times for admin approval, which writes them
onto the attendance record with a full audit trail.

### Holidays and calendar

`bin/rails hr_lite:seed` inserts the three fixed-date national holidays
(Republic Day, Independence Day, Gandhi Jayanti). Movable festival dates shift
every year, so leadership adds them under `/admin/holidays` — including a
bulk-paste flow. Everyone sees the holiday list at `/holidays` and a combined
company calendar at `/calendar`. The weekend rule (Sunday only, Saturday and
Sunday, or 2nd and 4th Saturday) is a leadership setting.

### Payroll and salary slips

Payroll runs one month at a time through
`draft → processing → review → finalized → published`. A run prorates each
salary structure by attendance, applies the statutory calculators, and produces
a salary slip per employee plus a payout-register CSV. Statutory rates live in a
date-keyed table so a budget change is one new entry and old runs keep computing
on the card that was in force:

```ruby
HrLite::StatutoryRateCard.for(Date.new(2026, 4, 1)) # => the card effective on/before that month
```

Leadership (or the superadmin tier, if set) drives runs under
`/admin/payroll_runs`; employees see their published slips at `/salary_slips`.
Salary-slip PDFs render through `config.render_pdf`, or through a built-in
WickedPdf path if `wicked_pdf` is in the bundle. The exact math, rounding rules
and what is deliberately not modelled are in `docs/PAYROLL.md` — read it with
your accountant before the first run.

### Kudos and @mentions

The kudos wall (`/kudos`) lets staff thank each other with @mentions. The picker
inserts a plain-text marker, `@[Asha Rao](42)`, and the server parses the ids
out of it:

```ruby
HrLite::MentionParser.user_ids("Great save @[Asha Rao](42)")  # => [42]
HrLite::MentionParser.strip_markers("Nice @[Asha Rao](42)")   # => "Nice @Asha Rao"
```

The autocomplete source is `GET <mount>/users/search?q=…`, backed by
`config.mentionable_users` (a name/email match on your user table by default;
override it to scope or to use your own search). Each mention notifies the
mentioned person; the marker is never shown raw in a bell or email.

### Notifications and the event bus

Domain code publishes an event; a per-event row in the notification matrix
decides which channels fire — an in-app bell, an employee email, a single
leadership email with every configured address in `To:`, and a leadership bell:

```ruby
HrLite::Notifications.publish(
  "leave.requested",
  title: "Asha requested casual leave",
  bell_to: HrLite.admin_users
)
```

The matrix is `HrLite::Notifications::DEFAULT_MATRIX`; override
`config.notification_matrix` to mute or add channels per event (a host matrix
pinned on an older gem version still works — unknown events fall back to the
defaults). Governing changes also publish `policy.changed` with a redacted diff
and land in the audit trail. The full event list and channel table is in
`docs/CONFIGURATION.md`.

### Appraisals, promotions and the org chart

Appraisals move `draft → shared` and become permanent once shared; employees
read theirs at `/appraisals`. Promotions and role changes are recorded as
designation changes with a timeline (`/career`) and can mirror into your own
user model through `config.on_designation_change`. The org chart at `/org` is
visible to everyone and shows the reporting tree — names, designations and
departments only, never salary or private data — with each viewer's own
reporting line labelled L1/L2/…

## Recurring jobs

Schedule these on the host's job scheduler (cron, GoodJob, Sidekiq-cron,
whatever you run). Each is idempotent and sends nothing on a quiet day.

| Job | Schedule | Purpose |
|---|---|---|
| `HrLite::DailyDigestJob` | each morning | Leadership digest: who is out today, pending approvals, flagged punches, missing checkouts |
| `HrLite::PayrollAutoDraftJob` | monthly, on the 1st | Draft and compute the previous month's payroll from attendance, then notify leadership for review (publishing stays a human action) |
| `HrLite::LeaveYearRolloverJob` | leave year's first day (Jan 1, or Jul 1 for a July–June year) | Materialize carry-forward into the new year's balances |

## Rake tasks

| Task | What it does |
|---|---|
| `hr_lite:seed` | Idempotently seed default leave types and the fixed national holidays. Safe to run on every deploy; it never overwrites operator edits. |
| `hr_lite:install:migrations` | Copy the engine migrations into the host's `db/migrate` (Rails-provided). Only needed if you want copies instead of gem-served migrations. |

## Generators

`hr_lite:install` writes `config/initializers/hr_lite.rb` and prints the
remaining wiring steps.

| Option | Default | Effect |
|---|---|---|
| `--route` | off | Also append `mount HrLite::Engine => "/hr", as: :hr_lite` to `config/routes.rb`. |

## Theming

Override the CSS variables, nothing else:

```css
:root { --hrl-accent: #00a24f; --hrl-font: "Inter", sans-serif; }
```

Point `config.extra_stylesheets` at a stylesheet and it is linked after the
engine's own CSS, so your `--hrl-*` overrides win. Every view is also
overridable through standard engine view precedence — drop a file at the same
path under your app's `app/views/hr_lite/…`.

## Statutory disclaimer

Payroll math (PF, ESI, PT, TDS) is projection-grade and configured in
`HrLite::StatutoryRateCard` — a date-keyed rate table. Verify the rates for each
financial year with your accountant before the first run; the per-slip LOP and
TDS overrides are the escape hatch. Surcharge, perquisites and HRA-exemption
math are not modelled — see `docs/PAYROLL.md` for the full list of what is left
to the override.

## Testing and development

The test harness is a minimal dummy app in `spec/dummy` — SQLite, a bare `User`
model and a session-based auth stub — so the suite runs in a few seconds with no
external services.

```bash
bundle install
bundle exec rspec            # dummy-app suite
COVERAGE=1 bundle exec rspec # with SimpleCov (the project holds 100% line coverage)
bundle exec rubocop          # rubocop-rails-omakase style
```

## Versioning

This project follows [Semantic Versioning](https://semver.org). While on 0.x a
minor release may include a breaking change, always called out in
[CHANGELOG.md](CHANGELOG.md); from 1.0 breaking changes land only in majors.

## Contributing

Bug reports and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for setup, the branch and PR flow, and the ground rules (Conventional Commits,
100% coverage, BigDecimal money, config hooks over host couplings, CI must
pass). Security issues: report privately per [SECURITY.md](SECURITY.md).
Everyone interacting with the project is expected to follow the
[code of conduct](CODE_OF_CONDUCT.md).

## Documentation

- [docs/CONFIGURATION.md](docs/CONFIGURATION.md) — every config key with type and
  default, the event/notification matrix, and how the access tiers gate.
- [docs/PAYROLL.md](docs/PAYROLL.md) — the exact payroll math, rounding rules,
  run lifecycle, and what is deliberately not modelled.
- [CHANGELOG.md](CHANGELOG.md) — release history.

## License

hr_lite is released under the terms of the [MIT License](MIT-LICENSE).
