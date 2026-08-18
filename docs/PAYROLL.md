# Payroll math reference

Everything the engine computes, the exact rounding rule applied, and what is
deliberately NOT modelled. Read this with your accountant before the first run
of any financial year.

## Rate card

Statutory numbers live in `hr_lite_statutory_rate_cards`, effective-dated,
edited on the rate-card screen (money tier). `StatutoryRateCard.for(month)`
picks the newest card effective on or before the run month, so correcting this
year never changes what an earlier month computed.

`HrLite::StatutoryRateCard::CARDS` is the SEED — the figures the gem ships,
copied in by `rake hr_lite:seed` and owned by the install from then on. It is
also the fallback for a host that has upgraded the gem but not yet migrated.

A card must start on 1 April and carry every figure payroll reads; a card
missing one is refused at save time rather than failing half way through
computing somebody's salary. Recording who verified it silences the
"not been marked verified" warning on every run.

**Shipping card (effective 2025-04-01) — verify each FY with a CA:**

| Item | Value |
|---|---|
| PF employee / employer | 12% / 12% of PF wage |
| PF wage ceiling | ₹15,000 (per-structure `pf_on_full_basic` opts out) |
| EPS split | 8.33% of EPS wage (ceiling ₹15,000), EPF = employer − EPS |
| EDLI / PF admin | 0.5% / 0.5% (employer cost lines) |
| ESI employee / employer | 0.75% / 3.25%, gross ceiling ₹21,000 |
| PT | `hr_lite_professional_tax_slabs`, per state and per date. Only Karnataka ships bands; an unconfigured state deducts ₹0 and the RUN SAYS SO |
| Income tax | new + old regime slab tables, §87A rebate cap, 4% cess |

### When no card ships for your financial year

The lookup never refuses — payroll cannot stop dead every 1 April — so it
falls back to the newest card it has. That silence is how a whole year gets
paid on last year's ceilings and slabs, so the run says it out loud instead:

- `StatutoryRateCard.stale_for?(month)` — the card in force belongs to an
  earlier FY than the run.
- `StatutoryRateCard.warning_for(month)` — the sentence naming both years.
  `PayrollRunProcessor` puts it FIRST in `payroll_run.warnings`, above every
  per-employee warning, on every compute, and it stays on the run screen
  through review and finalize.

**Adding a year is one new entry in `CARDS`** keyed to its 1 April, with the
figures confirmed against the year's Finance Act by your accountant. Nothing
else changes: past runs keep resolving to the card that was in force for them.

Rates are deliberately NOT inferred, extrapolated or defaulted forward. A
wrong slab is a wrong Form 16 for every employee, so the engine would rather
carry a loud warning than a confident guess.

## Per-slip pipeline (`HrLite::SlipBuilder`)

1. **Attendance summary** — `payable = days_in_month − out_of_window − LOP`.
   `out_of_window` covers days before joining / after exit (profile dates), so
   mid-month joiners are clipped exactly once. The review-stage `lop_override`
   replaces the attendance LOP entirely.
2. **Proration** — each structure component earns `full × payable/days_in_month`,
   rounded to paise per line (calendar-day basis).
3. **PF** — on earned basic: wage = `min(basic_earned, ceiling)` unless
   `pf_on_full_basic`. Employee and employer totals round to the nearest rupee;
   EPS wage stays ceiling-capped even on full-basic structures.
4. **ESI** — eligibility is decided on the FULL structure monthly gross in
   force on the first day of the ESIC contribution period (Apr–Sep / Oct–Mar),
   so a mid-period raise past the ceiling does not end coverage on the spot and
   a low-attendance month cannot pull someone in. Contributions apply to the
   earned gross and round UP to the next rupee (ESIC rule).
5. **PT** — slab lookup on earned gross; optional `feb_extra` per slab for
   February-top-up states.
6. **TDS** — projection basis:
   `projected annual = FY gross paid (published slips) + this month + structure gross × months remaining after this one`;
   `taxable = projected − standard deduction − (old regime: declared deductions)`;
   slab tax → §87A full rebate when taxable ≤ cap → +4% cess → §288B round to
   ₹10; `monthly = max((annual − TDS already deducted)/months remaining, 0)`.
   The per-slip `tds_override` short-circuits all of it.
7. **Net** = gross − sum of already-rounded deduction lines. No re-rounding, so
   totals can never drift from the printed lines.

The whole TDS working is stored on the slip (`tax_details`) and shown on the
admin review screen — "why is my TDS X" answers itself.

## Run lifecycle

`draft → processing → review → finalized → published`

- Recomputing in review preserves `lop_override` / `tds_override`.
- Finalize locks every slip (model-level guard, not UI).
- Unlock (finalized → review) exists for pre-publish corrections.
- Publish is terminal: slips become employee-visible, everyone is notified.
  Post-publish corrections are a future supplementary-run feature — today the
  answer is "fix it in next month's run".

## NOT modelled (by design — the override is the contract boundary)

- Surcharge above ₹50L taxable (the slip flags these and demands an override)
- HRA exemption, perquisites, prior-employer income (old-regime declarations
  are a single lump sum)
- Statutory filings (ECR/ESI returns/Form 16) — the register CSV is the
  handoff to whoever files
