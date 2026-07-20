# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/kshtzkr/hr_lite/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kshtzkr/hr_lite/releases/tag/v0.1.0
