# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-08-18

Access stops being three lambdas and becomes a role table. **Breaking**, with
an upgrade path that is designed not to be: the migration reads your own
configuration and lands everybody where they already were.

**Adds two migrations.** The first creates the role tables; the second seeds
the built-in roles and derives assignments from your existing email lists,
printing who it put where.

### Fixed

- **Any admin could approve anybody's leave.** Every admin screen gated on a
  tier and then acted on `Model.find(params[:id])`, so whoever could decide
  leave could decide everyone's. `manager_id` sat on the profile driving
  nothing but the org chart. There is now a Manager role at `team` scope,
  every list is narrowed through the relation, and every member action
  re-checks the row.
- **Two of the three tiers were a string match on `user.email`** — a mutable,
  host-owned, unverified column that each host had to remember never to let
  anybody edit. Roles are rows now.

### Added

- `HrLite::Permissions` — the declared vocabulary. A grant is a (role, key,
  scope) row, so an unknown key cannot be stored, and asking about one raises
  rather than quietly answering "no".
- `HrLite::Access` — resolves what somebody may do and whose rows it reaches,
  memoized per request. `can?`, `reaches?`, `visible_user_ids`,
  `scope_relation`.
- Controller helpers `hr_can?`, `hr_reaches?`, `hr_require_permission!`,
  `hr_require_reach!`, `hr_scope`.
- `HrLite.can?`, `HrLite.reaches?`, `HrLite.users_holding` for host code.
- A Roles screen (`/admin/roles`, behind `role.manage`) for grants and
  assignments. Built-in roles cannot be renamed or deleted, and the last
  person able to manage roles cannot be removed from the role that lets them.
- `rake hr_lite:roles`, and `hr_lite:seed` now seeds roles too.

### Changed

- `HrLite.admin?`, `.leadership?` and `.superadmin?` read off roles. They
  still exist because views, hosts and the notification fan-out call them.
- `config.legacy_tier_checks` (default `false`) hands authority back to the
  pre-0.6.0 lambdas for a host mid-migration. Honoured for one minor version;
  **removed in 0.7.0**.
- `HrLite.admin_users` is one query over the grant tables rather than
  instantiating every employee and asking.
- Branch-coverage floor 90% -> 90.5%.

## [0.5.3] - 2026-08-17

Correctness and traceability pass, ahead of the permissions work in 0.6.0.
**Adds one migration** — check constraints on every status column, plus an
index and foreign key on `hr_lite_designation_changes.appraisal_id`. It
refuses to run, naming the table and the offending values, if a live row
already holds a status no model declares.

### Fixed

- **Payroll ran silently on an out-of-date statutory card.** The lookup fell
  back to the newest card on or before the run month with no signal, so a run
  in a financial year the gem ships no card for computed PF, ESI, PT and TDS
  on the previous year's figures and said nothing. It still falls back —
  payroll cannot stop dead every 1 April — but `PayrollRunProcessor` now puts
  a warning naming both financial years at the TOP of the run's warnings, on
  every compute. Adding a year remains one new entry in
  `StatutoryRateCard::CARDS`; rates are never inferred forward.
- **A blank email could be granted the leadership tier.** `leadership_check`
  did not drop empty entries the way `superadmin_check` did, so one stray
  comma in `HR_LEADERSHIP_EMAILS` ("a@x.com,,b@x.com") put `""` on the list
  and any user whose email was blank or nil matched it. Both checks now share
  `HrLite.email_listed?`, which refuses a blank address against any list.
- Comp-off approval no longer reaches for a plural that cannot occur — a
  credit is 0.5 or 1 day and never more.

### Added

- **The money path leaves a trail.** Payroll compute, finalize, unlock and
  publish, every leave approval, rejection and cancellation, and the payout
  register download now write `AuditLog` rows. Previously a run could be
  computed, finalized, unlocked, edited and republished and the audit screen
  showed none of it.
  - These rows are written inside the same transaction as the change they
    describe and RAISE on failure, unlike the `Audited` concern, which stays
    best-effort for ordinary policy edits. A payroll transition nobody can
    account for afterwards does not happen at all.
  - Amounts are deliberately excluded — `audit_logs` is not encrypted. Rows
    record who moved a run, how far, and over how many people. Leave rows
    carry the approver's note and never the employee's own reason.
  - `HrLite::PayrollRun` and `HrLite::SalarySlip` join `MONEY_TIER_TYPES`, so
    payroll rows stay out of the leadership audit screen.
- `HrLite::AuditLog.record!` — the five-line `create!` that five call sites
  had each written out.
- `HrLite::FinancialYear` — the Indian FY (1 April) worked out in one place
  instead of three.

### Changed

- Statuses are enforced by the database. `update_column`, `update_all`,
  `insert_all` and console fixes can no longer write a value that no screen
  renders and no transition accepts.
- The suite enforces its own coverage: 100% line, 90% branch, 90% per file.
  The README claimed 100% and nothing checked it; switching the floor on found
  eight untested paths, including all three slip-override money guards (LOP
  above the days in the month, negative LOP, negative TDS) and the offboarding
  error path. All are covered now.
- `docs/PAYROLL.md` no longer lists ESI contribution-period lock-in as
  unmodelled — 0.5.2 implemented it.

## [0.5.2] - 2026-08-08

The rest of the audit that produced 0.5.1. **Adds three migrations** — they
run through the host's normal `db:migrate`; each table holds a handful of
rows per employee, so the builds are instant.

### Fixed

- **Payroll accepted a run for a month that had not ended.** Days that have
  not happened score as `upcoming`, which fed straight into payable days, so
  computing mid-month paid for every remaining day as if it had been worked —
  and finalizing froze that into immutable slips. `parse_month_param` made it
  easy to reach: a mangled month fell back to the current one.
- **ESI eligibility was re-decided every month.** ESIC contribution periods run
  April–September and October–March and eligibility holds for the whole
  period; a mid-period raise past the ceiling used to end coverage on the spot.
- **A mid-year install deducted no tax.** TDS projected the year only from
  slips this install produced, so earlier months — a previous employer, or the
  months before payroll was switched on — read as zero income and usually put
  the year under the rebate cap. `EmployeeProfile` gains `fy_opening_gross`
  and `fy_opening_tds`.
- Regularization now re-checks the approved-leave conflict at approval. Leave
  granted while the ticket waited made the fix a silent no-op, because
  full-day leave outranks any punch — while everyone was told attendance had
  been corrected.
- Admins can cancel leave. `cancellable_by?` always allowed it for approved
  leave that has not started, but no route reached it, so leave called off
  while someone was away could not be released and the quota stayed spent.
- One open resignation per person, one pending regularization per person per
  day, and one leave type carrying the comp-off flag are now enforced by
  partial unique indexes, not only by validations that race. Retiring the
  flagged comp-off type releases the flag so a replacement can take it.
- An employee whose resignation was already accepted can no longer file
  another, which would have overwritten the agreed exit date.
- `Audited` fires on commit. Firing inside the transaction announced changes
  to leadership that then rolled back — a failed onboarding mailed out a diff
  for a profile that was never saved.
- Slips record and show days outside the employment window, so a mid-month
  joiner's payslip adds up instead of looking short.
- The career page dates the current role from the change actually in force,
  not from a promotion recorded for next quarter.
- The org chart's reporting line stops at the first manager who has left; it
  used to skip them and promote everyone above a level, contradicting the
  tree below.
- Publishing no longer bells offboarded people at a page their revoked login
  cannot open. They still get the email.
- Leadership copies of employee-scoped notifications are named and point at a
  page leadership can open. "Your appraisal has been shared" linking to
  `/appraisals/7` was fanned out verbatim; the leadership copy also drops the
  rating, which is money-tier.

### Performance

- `LeaveBalance#used` builds one working calendar for the leave year instead
  of one per approved request — measured 11 queries down to 1 for five
  requests, and the admin balances grid multiplies that by employees × leave
  types.
- `HrLite.admin_users` starts from `employees_scope` rather than loading and
  instantiating every row in the users table on each admin notification.

## [0.5.1] - 2026-08-07

Bug-fix release from a full audit of the engine. No migrations, no
configuration changes required.

### Fixed

- **Every admin "Reject" button returned a 422.** The decision screens
  rendered one form pointed at the approve endpoint and retargeted the
  Reject button with `formaction:`. Rails binds the authenticity token to
  the form's own action and method (`per_form_csrf_tokens`, the default
  since `load_defaults 5.0`), so that token was never valid at the reject
  path. Comp-off, leave and regularization rejections could not be made
  from a browser at all. Each screen now renders separate Approve and
  Reject forms.
- **`PayrollRun#compute!` demoted any run — including a published one — to
  `draft`.** The `raise_unless` guard raised inside the method-level
  rescue, which then rewrote the status. Draft runs are deletable and the
  delete cascades over every salary slip. The guard now sits outside the
  rescue and the previous status is restored; a run stranded in
  `processing` is recoverable.
- **TDS was wrong on every slip from April to December**: months remaining
  in the financial year read `15 - month` instead of `16 - month`.
- TDS to-date counted published slips only, so a finalized-but-unpublished
  month projected as zero income; §115BAC marginal relief above the rebate
  cap was missing; a leaver's projection ran past their exit month.
- Net pay is floored at zero and the run warns when deductions exceed
  earnings. Review-stage LOP and TDS overrides are bounded.
- **A configured superadmin absent from `leadership_emails` was locked out
  of the money tier entirely.** `SuperadminController` no longer inherits
  the leadership check, and the Payroll nav item hangs off the money tier.
- Appraisal ratings and review text reached ordinary leadership through
  the audit screen and the `policy.changed` email; money-tier subjects are
  excluded from both.
- Accepting a resignation stamped an exit date, which hid the only control
  that revokes sign-in. The card stays, and access is revoked immediately
  when the last day has already passed.
- Onboarding created the login before validating the profile and outside
  any transaction, leaving orphaned role-bearing accounts behind.
- A backdated `DesignationChange` overwrote the current designation and
  pushed it to the host; only the newest row applies now.
- Editing a profile whose manager had exited silently cleared the
  reporting line, because the select offered no matching option.
- Leave: creation and approval use the same as-of date (future-dated
  requests on monthly accrual could be filed but never approved); approval
  locks the balance row rather than the request row; the stored adjustment
  has one locked write path; entitlement stops accruing at the exit date;
  the comp-off flag can be moved to a replacement leave type.
- Attendance: a check-out with no check-in is refused; clearing both times
  on a day with no punch no longer writes a bogus audit row or emails a
  removal that never happened; the punch card offers yesterday's check-out
  after midnight; `geo_status` is confined to what a browser can report.
- The overview board counts and lists comp-off and regularization, and the
  team attendance KPIs add up to the headcount again.
- One bad recipient no longer drops the rest of a notification fan-out.
- The slip PDF formats money like the web slip; amounts in words handle
  negatives and figures above ₹100 crore; professional-tax slabs gained an
  inclusive `from:` bound.

### Added

- A **More** tab on phones, opening a sheet with every nav item and every
  group the viewer is entitled to. Below 768px the left rail is hidden and
  the tab bar holds five items, so the rest of the app — including all
  admin, leadership and payroll screens — was unreachable.
- Confirmation prompts that actually run. The engine ships no Turbo, so
  its `data-turbo-confirm` attributes were inert and destructive buttons
  fired on the first click. A small script reads the same attribute and
  stands aside when a host does load Turbo.
- A retry policy on the engine's jobs, which had never inherited
  `ApplicationJob`.

### Documentation

- Reworked the README to open-source standard: a shields.io badge row, a table
  of contents, a per-feature usage guide (attendance and geolocation; leave,
  comp-off and regularization; payroll; kudos and @mentions; the notification
  bus), and sections for the recurring jobs, rake tasks and the install
  generator.
- Documented the leadership and superadmin (money) access tiers, and the
  `HR_LEADERSHIP_EMAILS` convention the generated initializer uses to keep the
  governing list out of a deploy.
- Filled gaps in `docs/CONFIGURATION.md`: the `superadmin_check`,
  `public_url_base`, `onboard_user`, `offboard_user` and `invite_url_for`
  keys, and the `resignation.*`, `employee.onboarded` and `payroll.draft_ready`
  rows of the notification matrix.

## [0.5.0] - 2026-07-20

### Added

- **Superadmin (money) tier** — `config.superadmin_emails`: only these
  people reach salary structures, payroll runs, slips administration,
  appraisals and promotions, or see salary/appraisal data on the
  employee page and the Payroll nav item. Ordinary leadership keeps
  governing people and policy. Empty list (default) = leadership keeps
  the money tier, exactly as before.
- **System-assigned employee codes**: prefix (Settings, default "EMP")
  + zero-padded sequence — EMP001, EMP002, … Forms no longer accept a
  code; changing the prefix starts a fresh sequence; explicitly-set
  codes (imports/seeds) are never overwritten.
- "New employee" button on the Employees screen.

## [0.4.0] - 2026-07-19

### Added

- **Org chart (`/org`)**: everyone-visible reporting tree (who reports to
  whom, names + designations + departments only — never salary or private
  data) plus each viewer's own reporting line labelled L1/L2/... Managers
  are set per employee by leadership ("Reports to"); reporting loops are
  rejected.
- **Configurable leave year** (`config.leave_year_start_month`, default 1):
  set 7 for a July–June leave year. Balances, accrual, the year-boundary
  split rule, carry-forward rollover and comp-off credits all follow it.
  Balance headings show "2026–27"-style labels for non-calendar years.
- **Joining-date proration, Keka-style**: entitlement accrues only from
  the month someone joins (joined on/before the 15th → that month counts;
  after → from the next month). Applies to monthly accrual AND
  yearly-upfront grants (upfront = remaining months × monthly rate).

### Changed

- `LeaveBalance#year` is now a LeaveYear key; `LeaveYearRolloverJob`
  defaults to the current leave year in the configured HR time zone
  (schedule it on the leave year's first day). The request-split
  validation message says "leave-year boundary".

### Upgrade notes

- **Set `leave_year_start_month` once, at install time.** Balance rows
  are keyed by leave year with no stored epoch — changing the start
  month on an install with existing balances silently reinterprets
  every row (carry, adjustments, comp-off credits) and miskeys
  historical requests. The setter validates 1..12 and accepts "7".
- **Joining-date proration applies to existing data.** Employees who
  joined partway through the CURRENT year previously showed the full
  year's accrual; from 0.4.0 they accrue only from their joining month,
  so their entitlement can drop (and, if they already used more, go
  negative). Where the old number was intended, add a one-off balance
  adjustment with a note.

## [0.3.0] - 2026-07-19

### Added

- **Comp-off requests**: employees request a credit for working a weekend
  or holiday; admin approval credits the comp-off leave type's balance
  (mark the type under Settings — seeds flag `CO`). New events
  `comp_off.requested/approved/rejected/cancelled`.
- **Regularization tickets**: forgot to punch? Employees propose the actual
  times with a reason; admin approval writes them onto the day's attendance
  record with the full regularization trail. New events
  `regularization.requested/approved/rejected/cancelled`.
- **Team board (`/team`)**: everyone-visible who's-in/who's-out for any
  date — punch times, leave badges, hours worked that day and that month.
- **Team leave notices**: approving a leave now bells + emails the whole
  team ("X is on leave …", matrix row `leave.team_notice`; reasons are
  never broadcast).
- Approvals screens grew Leaves / Comp-off / Regularization tabs with
  pending counts.

### Fixed

- Checkboxes rendered 100%-wide with misplaced labels (the bare
  `input[type]` width rule out-ranked `.hrl-field--check`); checkbox rows
  now size naturally and pick up the accent colour.
- Hardening from adversarial review: comp-off credits land in the year
  they can be spent (a December Sunday approved in January no longer
  strands the credit on last year's balance); the balance increment locks
  the balance row (no lost update when two admins approve concurrently);
  a partial unique index guarantees one live comp-off request per person
  per date; approval re-checks the calendar (StaleOffDay) after holiday
  edits; regularization approval refuses merges that would corrupt the
  record (checkout with no check-in, checkout before the genuine
  check-in) with the real reason surfaced to the admin, keeps GPS flags,
  and writes an AuditLog row like the manual fix path; tickets cannot
  target a day covered by approved leave; only one leave type can carry
  the comp-off flag; team notices skip exited staff; a host
  notification-matrix override pinned on an older version no longer
  silently drops events it doesn't know (defaults merge underneath).

### Changed

- `Seeds.run!` no longer re-flags CO as comp-off on every deploy (an
  operator disabling comp-off stays disabled); pre-0.3.0 installs run
  `Seeds.seed_comp_off_flag!` once or tick the box under Settings.

## [0.2.2] - 2026-07-19

### Fixed

- Link-styled controls were unreadable: the global `.hrl-body a` colour
  rule out-ranked component classes, so primary action links ("New
  structure", "New run", "Add office", "Apply", "Download PDF", active
  filter chips) rendered accent-on-accent with invisible text, and the
  side-nav links lost their muted colour. The rule is now wrapped in
  `:where()` (zero specificity) so every `.hrl-*` component wins.

## [0.2.1] - 2026-07-19

### Added

- Email-invite onboarding: leave the starting password blank and the
  welcome email carries a set-your-password link from the host's
  `invite_url_for` hook; `Notifications.publish`/`EventMailer.event`
  accept an absolute `link_url` for tokenized URLs. (Intended for 0.2.0;
  missed the merge window.)

## [0.2.0] - 2026-07-19

### Added

- Resignations: employees submit/withdraw from the portal; leadership
  accepts with a confirmed last working day that stamps the profile's
  exit date (payroll/attendance clip to it automatically).
- Onboarding: leadership creates the sign-in with the profile via the
  `onboard_user` hook (no self sign-up anywhere); offboarding stamps the
  exit date and revokes access via `offboard_user` — records are never
  deleted.
- `PayrollAutoDraftJob`: monthly automation that drafts + computes the
  previous month's payroll from attendance and notifies leadership for
  review; publishing stays human.
- Company logo (`company[:logo_url]`, data-URIs welcome) in the shell
  and on salary-slip PDFs.
- Keka-style left-rail navigation on desktop with grouped sections
  (My work / Team / Organisation); mobile keeps the bottom tab bar.
- New notification-matrix events: `resignation.*`, `employee.onboarded`,
  `payroll.draft_ready`.

### Fixed

- The auto-created settings row no longer emails leadership
  ("Someone created Setting" noise); real settings edits stay audited.

## [0.1.2] - 2026-07-19

### Fixed

- Slip PDF template no longer 500s when rendered by host code
  (`config.render_pdf`): amount-in-words is now a PORO
  (`HrLite::AmountInWords`), not a view helper, since engine helpers are
  not in scope under a host renderer. Caught live against a host app;
  regression spec renders the template through a bare controller.

## [0.1.1] - 2026-07-19

### Added

- `bin/demo`: one-command sandbox — fresh sqlite database, engine
  migrations from the gem, rich sample data (three persona tiers,
  attendance history, leaves, kudos, a published payroll run, a shared
  appraisal) and a click-to-sign-in persona picker.

### Fixed

- `hrl_money` Indian digit grouping (₹3,69,000.00 — previously mis-grouped).
- Layout `<title>` uses the configured company name instead of a
  hardcoded brand.

## [0.1.0] - 2026-07-19

Initial release.

### Added

- Attendance: geolocated check-in/out with office-radius flagging (never
  blocking), month grids, admin team day view and audited regularization.
- Leave: policy-driven types, hybrid live-computed balances, half-days,
  race-safe approvals, cancellations, holiday calendar with bulk paste,
  weekend policy (sun-only / sat-sun / 2nd-4th Saturday), company calendar.
- Payroll: versioned salary structures, date-keyed statutory rate card,
  PF/ESI/PT/TDS calculators, LOP-prorated runs with review overrides,
  publishable salary slips with PDFs and a payout register CSV. Money and
  identity PII encrypted at rest.
- Kudos wall with @mentions and badges.
- Appraisals (draft -> shared, permanent once shared) and promotions with a
  designation timeline and host sync hook.
- Three-tier access (employee / admin / configurable leadership), an event
  bus with per-event channel matrix (bell, email, leadership email/bell),
  daily leadership digest and an append-only audit trail.

[Unreleased]: https://github.com/kshtzkr/hr_lite/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/kshtzkr/hr_lite/compare/v0.5.3...v0.6.0
[0.5.3]: https://github.com/kshtzkr/hr_lite/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/kshtzkr/hr_lite/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/kshtzkr/hr_lite/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/kshtzkr/hr_lite/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/kshtzkr/hr_lite/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/kshtzkr/hr_lite/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/kshtzkr/hr_lite/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/kshtzkr/hr_lite/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/kshtzkr/hr_lite/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/kshtzkr/hr_lite/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kshtzkr/hr_lite/releases/tag/v0.1.0
