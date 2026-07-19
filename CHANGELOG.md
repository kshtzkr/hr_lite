# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
