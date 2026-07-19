# Configuration reference

Every `HrLite.configure` key, its default, and when to override it.

| Key | Default | Notes |
|---|---|---|
| `user_class` | `"User"` | Host user model name. Needs `id` + `email`; display name via the methods below. |
| `parent_controller` | `"ActionController::Base"` | Set to your `"ApplicationController"` so HR inherits auth/rate limits. Resolved once at boot — restart after changing. |
| `current_user_method` | `:current_user` | Called on the controller per request. |
| `authenticate_method` | `:authenticate_user!` | Any before_action-able method on the parent controller. |
| `admin_check` | `user.admin?` if defined | Operations tier: team attendance, regularization, leave decisions, overview board. Leadership implies admin. |
| `leadership_emails` | `[]` | THE governing list. Policy, offices, holidays, weekend setting, employee profiles, salary structures, payroll, appraisals, audit trail. |
| `leadership_check` | membership in `leadership_emails` (case-insensitive) | Replace to derive leadership some other way. |
| `display_name_method` | `:display_name` → `:name` → `:email` | First present value wins. |
| `employees_scope` | `user_klass.all` | Who HR tracks — override to exclude bots/service accounts. |
| `mentionable_users` | name/email `LIKE` on the user table | Backs the kudos @-autocomplete (`GET <mount>/users/search`). |
| `notify` | no-op | In-app bell hook: `->(user:, kind:, title:, body:, path:)`. `kind` is the event key; `path` is engine-relative. Exceptions are swallowed + logged. |
| `mailer_from` | `hr@example.com` | From-address for every HR email. |
| `mail_link_base` | `nil` | e.g. `https://hr.example.com` — enables the "Open in HR" button in emails. Unset = emails carry no links. |
| `notification_matrix` | `Notifications::DEFAULT_MATRIX` | Per-event channel routing — see below. |
| `leave_year_start_month` | `1` | First month of the leave year. `7` = July–June: balances, accrual, rollover, split rule and comp-off credits all follow it; schedule `LeaveYearRolloverJob` on that month's 1st. Entitlement always prorates from the joining date (≤ 15th counts that month). **Set once at install time** — balance rows are keyed by leave year, and changing the start month later reinterprets every stored balance. Validated 1..12 at assignment. |
| `render_pdf` | `nil` | `->(template:, assigns:, cache_key:)` returning PDF bytes. Unset: built-in WickedPdf if the gem is present, else PDF is disabled with a flash. |
| `company` | `{name: "Company"}` | Lambda → `{name:, address:, logo_path:}` for slips/emails/shell brand. |
| `time_zone` | `Asia/Kolkata` | Wraps every HR request (`Time.use_zone`). |
| `currency_symbol` | `₹` | Display only. |
| `on_designation_change` | no-op | `->(user, designation)` fired after every promotion/role change — mirror into your own user model here. Exceptions swallowed. |
| `extra_stylesheets` | `[]` | Host stylesheets linked AFTER `hr_lite.css` — override the `--hrl-*` CSS variables to retheme. |
| `back_link` | `nil` | `{label:, url:}` nav escape hatch back to the host app. |

## Events and the notification matrix

`HrLite::Notifications.publish(event, ...)` routes each event through four
channels; the matrix row (host-overridable) is the on/off table:

| Event | bell | email | leadership email | leadership bell |
|---|---|---|---|---|
| `leave.requested` | admins | — | ✓ | ✓ |
| `leave.approved` / `leave.rejected` | requester | requester | ✓ | — |
| `leave.cancelled` | admins | — | ✓ | — |
| `attendance.flagged` | admins | — | — (daily digest) | — |
| `attendance.regularized` | employee | employee | ✓ | — |
| `payroll.finalized` | — | — | ✓ | ✓ |
| `payroll.published` | each employee | each employee | ✓ | — |
| `kudos.mentioned` | mentioned | mentioned | — | — |
| `appraisal.shared` | employee | employee | ✓ | — |
| `promotion.recorded` | employee | employee | ✓ | ✓ |
| `policy.changed` (every governing-tier mutation, with change diff) | — | — | ✓ | ✓ |
| `digest.daily` | — | — | ✓ | — |
| `leave.team_notice` (fired on approval — "X is on leave", no reason) | whole team | whole team | — | — |
| `comp_off.requested` | admins | — | ✓ | ✓ |
| `comp_off.approved` / `comp_off.rejected` | requester | requester | approved only | — |
| `comp_off.cancelled` | admins | — | ✓ | — |
| `regularization.requested` | admins | — | ✓ | — |
| `regularization.approved` / `regularization.rejected` | employee | employee | approved only | — |
| `regularization.cancelled` | admins | — | ✓ | — |

To mute or add channels for one event:

```ruby
c.notification_matrix = HrLite::Notifications::DEFAULT_MATRIX.merge(
  "kudos.mentioned" => { bell: true, email: false, leadership_email: false, leadership_bell: false }
)
```

Leadership email fan-out is ONE message with every configured address in To:.
Encrypted attribute changes appear in diffs/audit rows as `[changed]` — never
plaintext.

## Access tiers (how gating actually works)

- **Employee** — every signed-in user; all self-service screens are scoped to
  `current_user` (a foreign id 404s). No role/permission needed, so a new hire
  is never locked out.
- **Admin** (`admin_check` OR leadership) — day-to-day operations.
- **Leadership** (`leadership_check` ONLY — admin is NOT enough) — anything
  that changes policy or money. Every mutation lands in the append-only
  `hr_lite_audit_logs` trail and emails leadership with the diff.
