# Payroll math reference

Everything the engine computes, the exact rounding rule applied, and what is
deliberately NOT modelled. Read this with your accountant before the first run
of any financial year.

## Rate card

All statutory numbers live in `HrLite::StatutoryRateCard::CARDS` — a frozen
hash keyed by effective date. `StatutoryRateCard.for(period_month)` picks the
newest card effective on or before the run month, so a budget change is one
new hash entry with a new date key (old runs keep computing on the old card).

**Shipping card (effective 2025-04-01) — verify each FY with a CA:**

| Item | Value |
|---|---|
| PF employee / employer | 12% / 12% of PF wage |
| PF wage ceiling | ₹15,000 (per-structure `pf_on_full_basic` opts out) |
| EPS split | 8.33% of EPS wage (ceiling ₹15,000), EPF = employer − EPS |
| EDLI / PF admin | 0.5% / 0.5% (employer cost lines) |
| ESI employee / employer | 0.75% / 3.25%, gross ceiling ₹21,000 |
| PT | per-state slab table; `none`, UP and Uttarakhand ship EMPTY (₹0) |
| Income tax | new + old regime slab tables, §87A rebate cap, 4% cess |

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
4. **ESI** — eligibility is decided on the FULL structure monthly gross (a
   low-attendance month cannot pull someone into ESI); contributions apply to
   the earned gross and round UP to the next rupee (ESIC rule).
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
- ESI contribution-period lock-in (Apr–Sep / Oct–Mar continuation after a
  mid-period raise) — re-checked monthly; `esi_applicable` is the manual lever
- Statutory filings (ECR/ESI returns/Form 16) — the register CSV is the
  handoff to whoever files
