# Security policy

hr_lite handles payroll amounts and identity documents (PAN, UAN, bank
details), so security reports get priority attention.

## Supported versions

| Version | Supported |
|---------|-----------|
| latest 0.x release | ✅ |
| older releases | ❌ — upgrade to latest |

## Reporting a vulnerability

**Do not open a public issue.** Instead either:

- use GitHub's private vulnerability reporting on this repository
  (Security → Report a vulnerability), or
- email **kshtzkr@gmail.com** with the details.

Include: affected version, a proof-of-concept or reproduction, and the impact
as you understand it. You will get an acknowledgement within a few days; fixes
for confirmed issues are released as patch versions with a CHANGELOG entry
crediting the reporter (unless you prefer otherwise).

## Scope notes for integrators

- All money amounts and identity PII columns use ActiveRecord encryption —
  the HOST app owns the keys; rotate them per Rails guides.
- The engine's authorization is layered: employee routes are self-scoped by
  construction, admin/leadership tiers gate via host-provided checks. If you
  override engine views or controllers, preserve those scopes.
- The audit trail (`hr_lite_audit_logs`) is append-only by model contract;
  do not add update/delete paths to it.
