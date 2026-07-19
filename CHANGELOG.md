# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
