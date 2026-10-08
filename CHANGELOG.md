# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Theming: new `--hrl-*` variables for the type ramp, line heights, spacing, large and pill radii, extra shadows, focus ring, motion, z-index, tap targets, and the colour roles `--hrl-ink-2`, `--hrl-field` and `--hrl-scrim`. The README lists every variable with its role.
- Keyboard: every focused control shows a 2px accent ring (kudos badge chips included), focus scrolls clear of the app bar and tab bar, and a "Skip to content" link is the first Tab stop so desktop users skip the side rail. Reduced-motion users get no transitions or animations. New `.hrl-sr-only` utility.
- Leave-type badge `.hrl-badge--type`: ink text on grey with an 8px dot in the HR-chosen colour, set inline as `--hrl-type`.

### Changed
- Engine defaults: `--hrl-radius` 14px to 16px, `--hrl-radius-sm` 9px to 12px, `--hrl-info-bg` #dbeafe to #eff6ff (accent text on it now 4.75:1) and `--hrl-muted` #6b7280 to #4b5563 (4.5:1 or better on the page background). Hosts that set these variables see no change.
- Type: every screen except the ID card uses the six-step ramp (12/14/16/18/20/24px) and weights 400/600/700. Nothing renders below 12px, and the page title grows from 20px to 24px at 768px.
- Radii: every corner outside the ID card is 12, 16 or 20px or a pill. Month-grid day cells go from 7px to `--hrl-radius-sm`, pills use `--hrl-radius-pill`, and the phone "More" sheet gets 20px top corners (`--hrl-radius-lg`).
- Long text: badges clip at their container's width, buttons wrap long labels, and definition-list values shrink instead of widening the page, so 60-character names no longer cause sideways scroll. Muted badges use `--hrl-ink-2`.
- Forms: inputs are 16px with a `--hrl-field` border (3:1 or better), an invalid field turns its border and label red, hints are styled everywhere, kudos chips and check-row labels are 44px tall with an 8px gap, and the error box is announced and takes focus. Mandatory fields carry `required`, so the browser stops an empty submit. `.hrl-card--warn` (expiring documents) now has its amber fill.

## [0.21.3] - 2026-10-09

### Fixed
- Phones: My attendance, the team calendar and an employee's attendance in admin no longer run wider than the screen once a month has punches; Sa/Su are back and check-in/check-out stack in each day.
- Phones: a long name or an email as the display name in the top bar no longer widens every screen and pushes the tab bar off.
- Phones: long links, file names and emails in policies, HR requests, appraisals, flashes and stacked tables (audit trail, approvals, team board, request lists) wrap instead of widening the page or hiding values.
- Admin employee profile with a salary card fits a phone; payroll and overview tiles go 2×2 below 1100px so amounts stay on one line beside the side rail.

## [0.21.2] - 2026-10-07

### Fixed
- HR recording leave for an employee on probation is no longer refused by the 1-day-a-month cap; the cap still applies when the employee applies themselves.

## [0.21.1] - 2026-10-07

### Fixed
- Admin "Team leave balances" now shows used/entitled per type, not only what is left.

## [0.21.0] - 2026-10-06

Three migrations: `hr_lite_employee_profiles.probation_until` (date),
`hr_lite_leave_requests.half_day_part` and
`hr_lite_attendance_records.half_day_part` (string).

### Added

- **Probation.** `config.probation_months` (e.g. 6) gives every new hire a
  `probation_until` date of joining + N months. HR edits it per employee on
  the profile form: blank removes the tag, a date adds or extends it.
  While on probation an employee can take at most 1 day of leave (any type,
  half days count 0.5) per calendar month; the request is refused at apply.
  A "Probation" badge shows on the employee list, the admin profile and the
  employee's own profile, and drops off by itself after the date.
  Existing employees are not tagged — the host backfills or HR sets them.
- **Full day / First half / Second half.** The leave forms (employee and
  HR-recorded) and HR's attendance day form use one "Day" picker instead
  of a half-day checkbox / status select. A half still counts 0.5; the
  label reads "05 Jul (first half)", and the team board shows which half.

## [0.20.2] - 2026-10-05

No migration.

### Changed

- **Leave team notice goes out on apply, by email too.** The whole team
  (minus the applicant) gets the bell and an email the moment leave is
  applied, not after approval. The reason is still left out. Hosts can
  mute either channel with the `leave.team_notice` matrix row.
- **A blocked location holds the punch.** Browsers ask for location once;
  after a "Don't allow" every later punch was filed without GPS and
  flagged. The punch now waits and tells the employee to allow location,
  then tap again. Timeout and no-GPS devices still punch (and flag).
- Team attendance board: "Fix / month" is now "Edit / half day", the
  screen where HR changes a marked day to a half day.

## [0.20.1] - 2026-10-03

Security fixes. No migration.

### Upgrading

Document numbers are now encrypted with Active Record Encryption. Rows
saved before this release are plain text, so the host needs
`config.active_record.encryption.support_unencrypted_data = true` to keep
reading them, and should re-save each `HrLite::Document` once to encrypt
the old numbers.

### Security

- **Nobody decides their own request.** A manager could approve their own
  leave, comp-off and attendance fixes, Finance its own expense claims, and
  anyone recording leave for someone else could record their own as
  approved. HR could verify or reject its own documents. All refused now.
- **Nobody edits their own records from the admin screens.** HR rewriting
  its own attendance, adjusting its own leave balance, or Finance verifying
  its own tax declaration is refused.
- **Document numbers are encrypted.** Aadhaar, PAN and passport numbers
  were stored in plain text and copied into audit diffs and the leadership
  audit email. Loans join the money tier for audit mail.
- **A rejected tax declaration no longer lowers TDS.**
- **Payroll CSVs defuse formulas.** Register and report cells that open
  with `=`, `+`, `-` or `@` are escaped, since names are staff-typed.
- **The payout register needs `payroll.export`**, not just
  `payroll.manage`.
- **The admin overview respects reach.** A team-scoped manager sees only
  the people they reach, not the whole company.
- **Expense receipts** take the same type and size rule as documents.

## [0.20.0] - 2026-10-01

Salary as CTC, and who is out today. No migration.

### Added

- **Fill from CTC.** The salary structure form takes an annual CTC, and
  "Fill from CTC" splits it: Basic is half the monthly CTC, HRA is 40% of
  Basic, the employer's PF and ESI are paid out of the CTC, and Special
  allowance takes the rest, rounding included. Nothing is saved until Save,
  which stores the lines shown; the CTC itself is never stored. A CTC too low
  for the split is refused. The form shows the monthly gross and CTC a
  structure works out to, and prefills the CTC on edit. Both use the rate
  card of the month the structure takes effect, and the typed CTC never
  reaches the audit log.
- **`SalaryStructure#breakup`** gives one month of a structure: earnings, the
  employee's PF, ESI and professional tax, the employer's PF and ESI, gross,
  CTC and in-hand, from the existing statutory calculators. ESI is decided on
  the salary that opened the ESIC period, as payroll does, and the yearly
  professional tax is summed month by month so a February top-up counts once.
- **My salary.** The salary slips page opens with the employee's current
  structure as a Monthly | Yearly table, a structure HR has saved for a later
  month ("New salary from …"), and earlier ones with their yearly CTC. Income
  tax stays on the slips. Slip release day does not hide the card.
- **Out today** on Home: everyone on approved leave today, by name, with the
  leave's dates (`01 Oct – 05 Oct`, or `01 Oct (half day)`), and a link to the
  Team board. The leave type is not shown, and staff who have left are not
  listed.
- **Team board** shows each leave's dates next to "On leave", and hovering a
  name on the board or on Out today reads "On leave: 30 Sep – 03 Oct".

### Fixed

- Form action buttons wrap on a narrow phone, so a third button no longer
  pushes the salary structure form sideways.

### Upgrading

No migration, no config.

## [0.19.0] - 2026-09-30

Each night closes the day. A missed check-out becomes a half day, and
employees can fix a recent missed punch themselves. No migration.

### Added

- **`HrLite::AttendanceCloseJob`**, scheduled by the host each night (a run
  before noon closes the previous day, so retries are safe). On a working
  day it checks out every punch still open at the day's end (23:59), marks the
  day `half_day` (payroll pays
  half and counts half as loss of pay), and emails the employee. Anyone who
  never checked in is emailed that the day is absent; no record is written.
  Weekends, holidays and approved leave (full or half day) are skipped. Run it
  once a day: a re-run emails the no-shows again.
- **Self-fix.** With `config.self_regularization = { within_days:, per_week: }`,
  a ticket that fills a missed punch on a working day, today or up to
  `within_days` back, is approved as soon as the employee submits it, for up to
  `per_week` days in a Monday–Sunday week. The punch is written the way an HR
  approval writes it, with the usual audit row, and nobody is notified. Older
  days, off days, fixes past the weekly limit, a change to a real punch, and a
  day HR already regularized or rejected go to HR as ordinary tickets; the
  flash says which happened. A check-out-only ticket for a day with no check-in
  stays pending for HR.
  `nil` (default) keeps HR as the only one who fixes punches. The ticket form
  states the rule when it is on.
- The Leaves page links "Record leave for someone" for anyone who can approve
  leave.
- The record-leave form says why somebody may be missing from the employee
  list (no HR profile yet). Leadership gets a link to set one up.

### Changed

- Approving a regularization ticket on a day the close job marked half day
  sets it back to present. A half day HR set on purpose stays.
- Approving a ticket for a month whose payroll run is in review adds a warning
  to that run, so the slip is recomputed before it is finalized.
- The admin overview and daily digest still count a day the close job checked
  out as a missing checkout.

### Fixed

- The sidebar, and the phone's More sheet, open scrolled to the current screen
  instead of the top. A Manage item such as Approvals is no longer below the
  fold.
- Page action buttons wrap on a narrow phone instead of running off the screen.

### Upgrading

Schedule `HrLite::AttendanceCloseJob` daily at `55 23 * * * Asia/Kolkata` in
your job scheduler (a run before noon closes the previous day). To let employees fix their own recent misses, set
`c.self_regularization = { within_days: 2, per_week: 2 }` in the initializer.
No migration.

## [0.18.0] - 2026-09-29

Salary follows leave. One migration (`paid_days` on leave requests, nullable;
existing rows read as fully paid).

### Changed

- **Leave beyond the balance is loss of pay, not refused.** On approval —
  applied by the employee or recorded by HR — the balance covers the leave's
  earliest working days in half-day steps (`paid_days`), and payroll cuts the
  rest at the month's gross divided by its calendar days. The balance is never
  overdrawn by it, so next month's accrual is not swallowed. Each unpaid day is
  cut in its own month when a leave spans two. The split is fixed at approval;
  correct it with the slip's LOP override while the run is in review.
- Comp-off is still refused past its earned credit.
- The monthly draft alert on the 1st goes to whoever runs payroll
  (`payroll.manage`), with email, instead of leadership — who cannot open it.

### Added

- The employee is told on applying how many days will be unpaid; the approver
  sees it on the request before approving.
- `config.slip_release_day` (1..28): employees see a published slip from that
  day of the following month, and the "slip ready" bell and email wait until
  then. `nil` (default) keeps today's behaviour. Needs an ActiveJob backend
  that runs scheduled jobs.

## [0.17.0] - 2026-09-29

Screens for the things other screens were waiting on. An audit of every HR
screen found four that could never show anything, because the rows they list
could only be created from a console. No migration.

### Added

- **Expense categories** (Settings → Expense categories, leadership). Until
  now nothing created one, so the claim form had no categories and every
  expense claim failed with "Category must exist". Add or edit name, monthly
  cap, receipt rule and active; untick Active to retire one (no delete —
  claims point at it).
- **One-off pay items** (Payroll → a run → One-off pay items, money tier): a
  bonus, incentive, arrears, reimbursement or one-time deduction for a person
  and month, carried by that month's computed slip. A month already paid
  refuses both adding and removing an item; the loan repayment line stays
  with the loan. Items are money-tier in the audit trail, so the leadership
  email no longer carries the amount.
- **Benefits admin** (Manage → Benefits, `benefit.manage`): add a benefit,
  enrol somebody with their dependants, end their cover. Employees' Benefits
  page was always empty before.

### Fixed

- **A manager could adjust anybody's leave balance.** The adjust action never
  asked whose balance it was. It now needs `leave.manage` reaching that person;
  the balances grid lists only people the viewer can see, and the adjust form
  shows only to someone who holds `leave.manage`.
- The professional-tax state picker on the salary structure form had no
  options.
- Sidebar links that led nowhere: the employee Approvals inbox shows only once
  an approval flow exists; Claims shows to whoever approves claims (Finance
  sees it, HR no longer lands on access denied); Profile is linked, and with it
  Resignation; both leave balance pages are linked.

## [0.16.0] - 2026-09-27

Employee ID cards, print requests through Ask HR, recording leave for
somebody, and notices that reach the right people. Two migrations, both
additive (`blood_group`/`emergency_contact` on profiles, `created_by_id` on
leave requests). New runtime dependency: `rqrcode`.

### Added

- **Employee ID card.** `/id_card` shows the card front and back; `/id_card/:user_id`
  lets anyone whose `profile.view` reaches that person open it to print. Print
  gives one CR80 (54 × 85.6 mm) face per page. The QR holds the company brand,
  address and phone as plain text — no URL, nothing to host.
- **ID photo.** The one field an employee edits on their own profile. JPG, PNG
  or WebP under 5 MB, content-sniffed; every change is audited.
- Blood group and emergency contact on the leadership employee form, encrypted
  like the other personal fields so the audit email reads `[changed]`.
- `config.company` may return `brand:` and `phone:`.
- **Request a printed ID card.** One tap on the card raises an Ask-HR request
  in the new `id_card` category. It needs a photo first, and only one can be
  open at a time. The desk opens the card from the request to print it;
  answering the request stamps "Issued" on the card.
- **Record leave for somebody.** Approvals → Record leave, for leave taken but
  never applied for. It is saved approved by whoever records it, keeps the
  balance check, stores `created_by_id`, and emails the employee — not the
  approvers. The employee is picked by typing a name or code.
- A new hire gets the Employee role with their profile, so Ask HR and
  Policies work from day one.
- **Publish policies and announcements.** Leadership (`policy.manage`) writes
  one at `/admin/policies`; every current employee gets an email and a bell.
  A policy asks to be acknowledged, an announcement does not, and reusing a
  title publishes the next version. The list shows who still has to
  acknowledge.
- **Holiday notices.** Adding a holiday tells everyone; a pasted list sends one
  notice, not one per line (new matrix row `holiday.published`).
- `config.notifications = ->(user) { { url:, unread: } }` puts a notifications
  link with the unread count in the HR shell. Off by default.

### Changed

- Notification defaults: a leave application and an Ask-HR request now EMAIL
  every approver / desk holder as well as belling them; the team "on leave"
  notice is a bell only, and is not sent at all for leave already over.
- Overlap and attendance errors on a leave request no longer say "you" — HR
  sees them too now.
- Employee codes are zero-padded to six digits, and the prefix may end in one
  hyphen — `ESA-` gives `ESA-000001`. Existing codes are left as they are.

## [0.15.0] - 2026-08-18

The screens for three features that shipped as tables nobody could reach. No
migration — the data layer was already there.

### Fixed

- **Documents, tax declarations and loans had no UI at all.** 0.13.0 and
  0.14.0 shipped their models, tables, payroll integration and an expiry job,
  and every one of them passed its specs — but there was no controller, no
  route and no view. An employee could not upload a passport, HR could not
  verify a PAN, and nobody could file an 80C declaration. Loans at least
  reached a payslip; the other two were unreachable rows.
- **A tax declaration 500ed when a real browser saved it.** The form posts a
  line for every section, because that is what a list of claimable things
  looks like, and the blank ones violated a NOT NULL amount. The specs had
  only ever posted the lines they filled in. Blank sections are now dropped,
  and clearing an existing amount withdraws that claim.
- `TaxDeclaration` and `ApprovalFlow` were missing `inverse_of` on their
  nested associations. The foreign key is not derived from the class name, so
  a nested item on an unsaved parent could not see it — every first save
  failed with "declaration must exist".

### Added

- **Documents.** Employees upload, see what is expiring and remove anything
  not yet verified; HR sees what is waiting, whose file is missing which
  category, and verifies or sends one back with a reason. Downloads go
  through the row's own `readable_by?` and every one is audited — a file
  leaving the building is the event worth recording.
- **Tax declarations.** A section-by-section claim the employee files
  themselves, replacing an admin typing one lump sum into the profile. HR
  records what the proof actually supported, which is often less than the
  claim. Until it is verified payroll deducts against the CLAIM: making
  somebody overpay tax all year because paperwork is slow is its own kind of
  wrong.
- **Loans.** Employees see what they owe and what comes out of the next
  payslip; the money tier records a loan, closes it, or cancels one that has
  not been deducted from yet. Cancelling after an instalment has been taken
  is refused — that money has already left somebody's salary.
- Nav entries for all three, employee and admin.

### Changed

- Verifying a document requires being able to OPEN it. Attesting to a scan
  you are not allowed to look at is not verification, and it keeps an
  Aadhaar with the money tier rather than with whoever happens to run HR.
- The spec suite deletes its sqlite file before every run. The role and
  rate-card migrations SEED rows, and seeds never overwrite what exists —
  right in production, wrong in a test database, where a leftover file kept
  yesterday's definitions and a change to `RoleSeeds` silently did not apply.

## [0.14.0] - 2026-08-18

The admin half, plus the two ends of employment that were still manual.
**Adds one migration.**

### Added

- **Admin screens for everything shipped since 0.11.0**: decide a claim and
  record the payroll month it was paid with, answer or hand on a help-desk
  request, hand out and take back an asset. The engine had all of this; there
  was no way to do any of it.
- **Assets.** One live holder at a time, enforced by a partial unique index —
  two open assignments would mean the laptop is in two places, which it is
  not. Assignments are append-only and record what condition it came back in,
  because "screen cracked" is the difference between an asset returned and an
  asset written off.
- **Joining and leaving checklists**, from templates. The joining list opens
  when a profile is created and the leaving list when an exit date is
  stamped — the checklist nobody remembers to start is the one that does not
  happen. Opening is idempotent, so adding a template later adds only what is
  new. A failure to build one can never stop an employee being created.
- Each step names the permission its owner should hold, so IT taking back a
  laptop and HR collecting a document are not the same person by accident.
- Permissions `asset.view`, `asset.manage`, `checklist.manage`.

### Why it matters

An asset that is never returned is a cost nobody notices, and access that is
never revoked is a security problem that outlives the employment. Both were
previously somebody's memory.

## [0.13.0] - 2026-08-18

The screens. No migration.

### Added

- **Employee self-service for everything built since 0.11.0**: claim an
  expense (with what is left of each cap shown before you type an amount),
  see what you are covered for, read and acknowledge a policy, ask HR a
  question and read the answer.
- **A reports hub** — headcount, joiners and leavers, leave balances,
  attendance and expenses — each with a CSV download, and each **scoped by
  the same permission that guards the screen its data comes from**. A report
  is not a side door into rows somebody cannot otherwise reach: a manager's
  headcount is their own team. The hub lists only the reports the reader can
  actually open, since a list of links that turn you away is worse than a
  short list.
- CSV downloads are audited, the same way the payout register is.

### Fixed

- **The reports hub locked Finance out of the expense report.** It inherited
  the operations gate, and Finance approves expenses but runs none of the
  operations screens. Found by writing the spec for it.

### Changed

- `.hrl-prose` for long-form policy text, capped at 68 characters a line — a
  policy read across the full width of a laptop is a policy nobody finishes.
- The demo sandbox seeds an expense claim, a benefit enrolment, a policy
  awaiting acknowledgement and an open HR request, so the new screens have
  something on them at first boot.

## [0.12.0] - 2026-08-18

The four things an employee had to leave the system to do. **Adds one
migration.**

### Added

- **Expenses**, with categories carrying a monthly cap and a receipt rule.
  The cap is checked when the claim is MADE, not at approval — telling
  somebody they are over it after a week of waiting is the wrong moment to
  find out. A claim awaiting a decision counts against the cap; a rejected
  one gives the room back.
- Expenses route through the approval engine from 0.9.0 rather than growing a
  fifth approve/reject. Configure a flow and a claim gets manager-then-finance
  for free. `reimbursed` is a separate state from `approved`, because agreeing
  to pay somebody and paying them are different days and the person waiting
  cares about the second one.
- **Benefits and enrolments.** Dependants are a COUNT, not a list — names and
  dates of birth of somebody's family are data this engine has no reason to
  hold, and holding them would mean protecting them.
- **An HR help desk**: raise, assign, resolve, with the answer going back to
  the person who asked instead of dying in somebody's inbox.
- **Policies, versioned.** Re-issuing asks everybody again, because an
  acknowledgement of v1 says nothing about v2 — that is the whole point of
  versioning it. Acknowledgements are `readonly?` once written: evidence that
  can be edited afterwards is not evidence. Clicking twice is not an error.
- Permissions for all four, granted to the roles that should hold them, and
  nine notification events.

### Changed

- `HrLite::Expense` is the second module on the approval engine, which is the
  first real test of the claim made in 0.9.0 that a new module gets
  multi-level approval without touching the engine. It did.

## [0.11.0] - 2026-08-18

Documents, and a tax declaration that is more than one number. **Adds one
migration.** Requires Active Storage on the host (`rails active_storage:install`).

### Added

- **`hr_lite_documents`** — there was nowhere to keep an employee's documents
  at all. Files attach through Active Storage, which content-sniffs via
  Marcel, so the type allowlist checks real bytes rather than what the client
  claimed. SVG and HTML stay out: both carry script and both render in a
  browser. 10 MB cap.
- **Visibility is a property of the row**, and an identity document defaults
  to the tightest setting rather than the convenient one — an Aadhaar, PAN,
  passport or bank mandate is money-tier by default, not HR's to browse. A
  default nobody thinks about is the one that leaks. An explicit choice always
  wins, which is why the column carries no default of its own.
- Verification with a named checker, and expiry with a job that warns at 30
  days and again at 7 — not daily, because a warning that arrives every day
  is one nobody reads by the third.
- **`hr_lite_tax_declarations`** and items, replacing
  `declared_annual_deductions`: ONE opaque figure an admin typed in, that
  nobody could see the makeup of, that the employee could not submit
  themselves, and that had nowhere to keep the proof. It is the number the
  whole year's TDS is projected from.
- Sections (80C, 80D, 80CCD(1B), 24(b), HRA), each with what was **declared**
  and what the proof actually **supported**. Until HR has looked, the declared
  figure stands — asking somebody to overpay tax all year because paperwork is
  slow is its own kind of wrong. Once verified, only the supported figure
  counts.
- The regime follows the declaration, because choosing one is a per-YEAR
  decision and the profile column cannot express that.
- Permissions `document.view`, `document.manage`, `tax.view`, `tax.manage`,
  granted to the roles that should hold them.

### Changed

- `SlipBuilder` reads the declaration when one exists for the run's financial
  year, falling back to the profile figure otherwise. A DRAFT declaration is
  ignored — a draft is not a claim.

## [0.10.0] - 2026-08-18

Payroll gets heads, arrears and loans. **Adds one migration.** Existing
payslips compute identically — every new head is opt-in data.

### Added

- **`hr_lite_salary_components`** — earning and deduction heads as DATA.
  Payroll knew exactly four earnings because they were columns on the salary
  structure, so a bonus, an incentive, an LTA or a reimbursement had nowhere
  to go but "other": one number on a payslip that should have said what it
  was for. Seeded with bonus, incentive, arrears, LTA, reimbursement, loan
  repayment and other-deduction; an install adds its own.
- Each head declares whether it is **prorated** (a bonus is not halved
  because somebody joined on the 16th), **taxable**, and whether it
  **counts toward the ESI gross** — a reimbursement is not a wage, and
  counting it could push somebody over the ceiling and out of cover.
- **`hr_lite_payroll_line_items`** — one-offs for a single month, including
  arrears after a backdated revision. Dated to the MONTH rather than the run,
  so deleting a draft and computing it again does not lose them. Refused on a
  month already published: that slip is immutable, and a later line would
  show on no payslip while quietly moving the year-to-date the TDS projector
  reads.
- **`hr_lite_loans`** and repayments. The outstanding balance is DERIVED from
  the repayments actually taken, never stored — a stored balance and a
  recomputed run disagree the first time somebody deletes a draft. The last
  instalment takes only what is left.
- Repayments are booked when a run is **finalized**, not at compute: a draft
  is recomputed as often as the operator likes, and each pass would otherwise
  take another instalment. Unlocking a run gives them back, and reopens a
  loan that had closed.

### Changed

- Branch coverage is now a **floor at 90%, not a ratchet**, with the reasoning
  written into `spec_helper.rb`. Its denominator grows with every subsystem,
  so ratcheting it charges each feature PR a tax for branches in files it
  never touched. Line coverage remains the ratchet at 100% overall and 90%
  per file — that is the gate that has actually caught defects.
- Paid down some of the branch debt named in 0.9.0: the status predicates
  across six models, the UAN format validation, and the holiday bulk-import
  paths (blank lines, an empty paste, a line that cannot be read).

## [0.9.0] - 2026-08-18

A reusable approval engine. **Adds one migration** (flows, steps, approvals,
delegations). Nothing changes for a module until a flow is configured for it,
which is what lets the four existing ones migrate one at a time.

### Fixed

- **Cancelling a leave request left its approval sitting in somebody's
  inbox.** Found by the coverage floor, which flagged `cancel_all!` as
  unreachable — it was written and never called.

### Added

- `HrLite::ApprovalFlow` / `ApprovalStep` / `Approval` / `ApprovalDelegation`.
  A flow is "leave needs the manager, then HR". A step names its approver by
  RULE — manager, manager's manager, anyone holding a permission, or one named
  person — so a flow survives somebody leaving; the rule resolves against the
  subject when the request is raised.
- Multi-level, sequential routing, with a `unanimous` step for the rungs where
  everybody has to answer rather than the first person to look.
- **A rung nobody occupies is skipped**, not left waiting. An employee with no
  manager recorded would otherwise have a request no living person could
  decide.
- **Delegation.** "I am away until the 14th — Priya decides for me." The
  approval does not move; a stand-in may answer it, and the row records both
  who it was addressed to and who actually decided. Two hops, so a stand-in
  who is also away is covered, and a loop cannot hand somebody their own
  approvals back.
- **SLA and escalation.** A step may carry a deadline; `ApprovalEscalationJob`
  tells an approver once per overdue row, grouped into one message per person,
  and stamps the rows so a daily run does not nag daily. Escalation TELLS
  somebody — it does not reassign, because a decision made by somebody who
  never saw the request is worse than a late one.
- **One approval inbox** (`/approvals`) replacing four places to look. Employee
  tier: holding an approval is the authorisation, so a manager, a stand-in and
  a director reach the same screen and each sees only their own rows. It sits
  after Calendar in the nav — the phone tab bar shows the first four, and this
  screen is empty for anybody who is not an approver.
- `HrLite::Approvable` — opts a model in WITHOUT taking over what its decisions
  mean. `LeaveRequest` keeps its own `approve!`, including the balance lock;
  the concern only answers "is it this person's turn, and does their answer
  settle it". A settling decision runs the ordinary transition, so routing
  never becomes a second path that can drift from the first.

### Changed

- `LeaveRequest` is the first module routed. With no flow it behaves exactly
  as before, and somebody outside the current rung who holds `leave.approve`
  at `all` can still settle it outright — the routed path is the normal one,
  not the only one.
- Branch-coverage floor 90.8% -> 90.3%, deliberately, with the arithmetic
  written into `spec_helper.rb`: the engine added ~90 branches at once, and
  holding the percentage would have meant contriving specs for untouched
  files. Line coverage stayed at 100%.

### Not yet

- Comp-off, regularization and resignation still use their own single
  decision. They are declared approvable and migrate next, one release each.

## [0.8.0] - 2026-08-18

The deprecation 0.6.0 opened, closed. **Breaking** only for an install still
setting `config.legacy_tier_checks`; no migration.

### Removed

- **`config.legacy_tier_checks` and the pre-0.6.0 tier lambdas no longer
  decide access.** `HrLite.admin?`, `.leadership?` and `.superadmin?` read
  roles, full stop. Two of those lambdas matched the user's `email` — mutable,
  host-owned, unverified — and a host that kept the flag on kept that hole
  open.
- The flag is gone from the configuration object entirely, so an initializer
  that still sets it now fails loudly at boot rather than silently doing
  nothing. That is the intended way to find out.

### Changed

- `admin_check`, `leadership_emails` / `leadership_check` and
  `superadmin_emails` / `superadmin_check` remain on the configuration, and
  are now **migration input only**: the 0.6.0 upgrade migration reads them to
  derive role assignments. An install jumping 0.5.x → 0.8.0 in one step still
  needs them present for that migration to have something to read, which is
  why they were not deleted outright. Setting them on a current install has no
  effect on who can reach what.
- `HrLite.leadership_users` and `.admin_users` are one query over the grant
  tables. The legacy paths that instantiated every employee and ran a host
  lambda per row are gone.

### Upgrading

If you set `legacy_tier_checks = true`, delete that line. Before you do, open
the Roles screen and confirm the people who need access hold it — the 0.6.0
migration will have assigned them already unless you had turned the flag on
before it ran.

## [0.7.0] - 2026-08-18

Statutory figures stop being code. **Adds one migration** (rate cards and
professional-tax slabs) and seeds it from the figures the gem already
shipped — no number changes on upgrade.

### Fixed

- **Every state except Karnataka deducted ₹0 professional tax, silently.** PT
  is a state levy and only Karnataka had bands in code; every other state
  resolved to an empty slab list and deducted nothing, which is a wrong answer
  delivered confidently. Slabs are now per state and effective-dated, and a
  run whose employees sit in a state nobody has configured says so — once per
  state, not once per employee.
- **Adding a financial year needed a gem release.** Every April was a deadline
  the gem controlled and the company did not; 0.5.3 shipped a warning about
  exactly that. Cards are rows now, entered on a screen.
- A tax regime saved with an empty slab list validated on key presence and
  then taxed every salary at zero. Refused.

### Added

- `hr_lite_statutory_rate_cards` — PF, ESI and both regimes' slabs per
  financial year, effective-dated. A card must start on 1 April (a mid-year
  card would mean two slab sets inside one year, and the TDS projector works
  on an annual figure), and must carry every figure payroll reads — a card
  missing one fails at save time rather than half way through computing
  somebody's salary.
- `hr_lite_professional_tax_slabs` — per state, per date, with the February
  top-up the states that levy one need.
- A rate-card screen (money tier). Adding a year copies the newest card, since
  most years carry PF and ESI over untouched and move only the slabs — a blank
  form would invite retyping eight numbers that were already right.
- **Sign-off.** A card records who checked it and when, and payroll warns on
  every run computed against one nobody has confirmed. Ranked below the
  wrong-financial-year warning: bad figures matter more than missing paperwork.
- `rake hr_lite:statutory`, and `hr_lite:seed` copies the shipped figures in.

### Changed

- `StatutoryRateCard.for` reads the table, falling back to the shipped hash
  for a host that has upgraded the gem but not yet run `db:migrate` — payroll
  must not 500 on a missing table.
- Branch-coverage floor 90.5% -> 90.8%.

### Deferred

- **`config.legacy_tier_checks` and the pre-0.6.0 tier lambdas are still
  here.** 0.6.0 said they would go in this release. They have not: removing an
  access mechanism in the same release that rewrites where statutory figures
  live puts two unrelated upgrade risks in one step, and this release is
  otherwise purely additive. They go in **0.8.0**, on their own. If you are
  still relying on the flag, the 0.6.0 migration has already created the
  equivalent role assignments — turn it off and check the Roles screen.

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

[Unreleased]: https://github.com/kshtzkr/hr_lite/compare/v0.15.0...HEAD
[0.15.0]: https://github.com/kshtzkr/hr_lite/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/kshtzkr/hr_lite/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/kshtzkr/hr_lite/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/kshtzkr/hr_lite/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/kshtzkr/hr_lite/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/kshtzkr/hr_lite/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/kshtzkr/hr_lite/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/kshtzkr/hr_lite/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/kshtzkr/hr_lite/compare/v0.6.0...v0.7.0
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
