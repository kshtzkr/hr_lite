# Silent failures audit (2026-10-21)

Every `rescue`, swallowed JS failure and unchecked write in `app/`, `lib/` and `app/assets/javascripts/hr_lite/`.
"Fixed" rows ship in 0.59.0. "OK" rows were read and left alone, with the reason.

| Where | What fails | What the user saw before | Now | Kind |
|---|---|---|---|---|
| 24 `rescue ActiveRecord::RecordInvalid` in admin and employee controllers (leave, WFH, comp-off, regularization, expenses, assets, HR requests, CA reviews, tax declarations, work locations) | `save!` inside a decision | A fixed line such as "Only pending requests can be decided.", even when the real cause was a validation | **Fixed.** `reason_for(e, fallback)` shows the record's own errors. The old line stays for the not-pending case | user |
| `Admin::EmployeesController#offboard` | Host `offboard_user` hook raises | "Offboarded, access revoked." when it was not | **Fixed.** An alert says access was NOT revoked, why, and to revoke it by hand | user |
| `Resignation#revoke_access!` (accepting on or after the last day) | Same hook | "Resignation accepted", with nothing about access | **Fixed.** `access_error`, shown as an alert | user |
| `DesignationChange#apply_to_profile` | Host `on_designation_change` hook raises | "Role change recorded." | **Fixed.** `hook_error`, shown as an alert | user |
| `Admin::AttendancesController` punch removal | `destroy` returning false | "Punch removed." | **Fixed.** `destroy!` | user |
| `search.js` | Fetch fails or returns non-2xx | Empty results, read as "nothing found" | **Fixed.** "Search failed. Check your connection and try again." | user |
| `tax_preview.js` | Same | A stale estimate, presented as current | **Fixed.** The panel says the tax could not be worked out and that Save still works | user |
| `crm_picker.js` | Same | "No lead", read as no matches | **Fixed.** "Lead search failed. Type again to retry." | user |
| `mention.js` | Same | The menu silently did not open | **Fixed.** "Could not load names. Keep typing to retry." | user |
| `photo_crop.js` | The browser cannot decode the picture (HEIC on desktop) | Nothing happened | **Fixed.** An alert asks for a JPG or PNG, and the input is cleared | user |
| `geo_punch.js` | Location denied or unavailable | Already shown, with steps (the model for this audit) | OK | user |
| `share.js` | Image render fails | Already alerts | OK | user |
| `ApplicationController#parse_month_param` / `#parse_date_param`, `RepeatRule#to_date`, `WorkModeDurations.parse_date`, `WorkModeSwitch#parse_until`, holiday bulk parse, regularization time parse | A mangled date in a URL or field | Falls back to today, or the model refuses with its own message (holiday import lists the bad lines) | OK. A fallback, not a failure | user |
| `EncryptedMoney` | Unreadable money input | Collected and refused by validation | OK | user |
| `WorkModeDurations` period error | Bad period | Returned and rendered as `@period_error` | OK | user |
| `WorkModeSwitch` RecordInvalid | Status change refused | The record's errors become the result message | OK | user |
| `LeaveBalance.lock_for`, `Policy#acknowledge!`, `AttendancePuncher` RecordNotUnique, `CalendarMeetingStartJob` RecordNotUnique | A concurrent insert race | Nothing, because the other writer won and the result is the same | OK. Not a failure | race |
| `RegularizationRequest` InvalidMerge on create | The auto-apply cannot merge | The request still goes to an approver, who sees the merge error on apply | OK | user |
| `ProfessionalTax.stored_slabs`, `StatutoryRateCard.stored?` | Host mid-migration | Shipped figures used | OK, documented in code | config |
| `HrLite.safe_url?` URI error | Bad return URL | Treated as unsafe | OK | security |
| `PayrollComputeJob` | Compute raises | A warning on the run page with the cause, plus `Rails.error.report` | OK. Already visible | background |
| `PayrollRun` compute rollback | Same | The status is restored and the job above reports it | OK | background |
| `Notifications` (3 rescues), `HrLite.notify`, `WfhRequest#notify`, work-location notify (2 controllers) | One email, bell or notification fails | Nothing. The action itself succeeded | Fixed in 0.60.0: recorded as `failure.<event>` in the audit trail and listed on the HR overview's "Failed in the background" card | background |
| `Audited` | An audit row fails to write | Nothing. The domain write must not roll back | Fixed in 0.60.0: same audit row and overview card | background |
| `EmployeeProfile#open_onboarding_checklist` | The checklist cannot open | The employee is created without a checklist | Fixed in 0.60.0: same audit row and overview card | background |
| `CalendarMeetingSyncJob` calendar read | The Google read fails | No meeting mode for that user | Fixed in 0.60.0: same audit row and overview card | background |
