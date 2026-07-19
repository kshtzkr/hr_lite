# Contributing to hr_lite

Thanks for helping! Issues and pull requests are welcome.

## Development setup

```bash
git clone https://github.com/kshtzkr/hr_lite.git
cd hr_lite
bundle install
bundle exec rspec            # dummy-app suite (sqlite, no services needed)
COVERAGE=1 bundle exec rspec # with SimpleCov
bundle exec rubocop          # rubocop-rails-omakase style
```

The test harness is a minimal dummy app in `spec/dummy` — sqlite, a bare
`User` model and a session-based auth stub — so the whole suite runs in a few
seconds with zero external dependencies.

## Ground rules

- **Tests required.** The project holds 100% line coverage; new code ships
  with specs (`COVERAGE=1 bundle exec rspec` must stay at 100%).
- **Money is BigDecimal.** Never `Float` in payroll paths; rounding goes
  through `HrLite::Money` (one statutory rule per line, applied once).
- **No new host couplings.** Anything host-specific goes behind a
  `HrLite.configure` hook with a sensible default — see
  [docs/CONFIGURATION.md](docs/CONFIGURATION.md).
- **Migrations are append-only** once released; schema changes ship as new
  migrations, and both leadership-mutable models include `HrLite::Audited`.
- **Statutory changes** (tax slabs, PF/ESI rates): add a NEW date-keyed entry
  to `HrLite::StatutoryRateCard::CARDS` with a source link in the PR — never
  edit an existing card, old payroll runs recompute against history.
- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`…), one logical change per commit.
- Style is `rubocop-rails-omakase`; run `bundle exec rubocop -A` before
  pushing. No emoji in code or user-facing strings.

## Pull requests

1. Fork, branch from `main`.
2. Make the change with specs; keep the diff focused.
3. Update `CHANGELOG.md` under `[Unreleased]` for user-visible changes.
4. Open the PR — CI must be green (lint + full suite).

## Releases (maintainer)

SemVer. Update `lib/hr_lite/version.rb` + `CHANGELOG.md`, then
`bundle exec rake release` (tags, pushes, publishes to rubygems — MFA
required).

## Questions / security

Questions → GitHub Discussions or an issue. Vulnerabilities → see
[SECURITY.md](SECURITY.md) (please do not open public issues for those).
