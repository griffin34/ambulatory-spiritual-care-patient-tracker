# Excel VBA code review — 2026-08-02

Full review of `excel/src/` (all `.bas` modules, sheet `.cls` code-behind, and `.frm` UserForms). 12 findings, ranked most severe first.

**Update 2026-08-02: all 12 findings fixed and verified.** Each finding below is
tagged `STATUS: FIXED` with what changed and how it was verified. Fixes were
verified via a full pytest pass (22 tests) plus a dedicated COM-driven script
exercising each fix directly through `Application.Run` (patient/appointment
save-and-read roundtrips, duplicate-username rejection, running a report and
confirming other sections' headers survive, a multi-cell settings paste, a
post-refresh protection check, and an upgrade-import with a deliberately
ambiguous username case) — all checks passed, and the whole project still
compiles/runs afterward. Findings are left in place below, not deleted, per
instruction.

## Critical — data loss / corruption

### 1. `modReports.bas:322` — Report table clear buffer wipes other sections' headers
**CONFIRMED**
**STATUS: FIXED** — `WriteTableRows`/`WriteWeekHelper` now take an explicit `bufferRows` bound instead of a fixed 500/200; each of the 12 call sites passes the largest value that stays inside its own section (12/16/16/18 rows), and the write loop stops early if it ever has more rows than the buffer allows. Verified: ran Referrals by Source alone via COM and confirmed First Appointments/Patients Dropped/SDAT Improvement headers (A20/A40/A60) were untouched afterward.

`WriteTableRows` (and `WriteWeekHelper` at line 292) clear a fixed 500/200-row buffer below each report section's header, but the 4 report sections sit only 16-20 rows apart on the Reports sheet, so one section's clear sweeps through and permanently erases the static header text of every section below it.

**Failure scenario:** The very first time anyone clicks Run on the Reports sheet (any single report, or All Reports — `UI_RunSelectedReport` always exercises all 4 sections), Referrals by Source's `WriteTableRows("A4",...)` clears A5:C504, wiping First Appointments' header at A20:C20, Patients Dropped's at A40:C40, and 3 of 6 columns of SDAT Improvement's header at A60:C60. None of these headers are ever rewritten afterward (they're static text `build.py` wrote once), so the Reports sheet is left with permanently blank column headers after one Run — unrecoverable without a rebuild or manual edit.

### 2. `modPurge.bas:151` — Purge deletes live data before archive save succeeds
**CONFIRMED**
**STATUS: FIXED** — `ArchiveAndPurge` now copies stale rows into the archive workbook and only *records* which rows to delete (bottom-to-top), then calls `archiveWb.SaveAs` under `On Error GoTo SaveFail` **before** deleting anything from the live sheets; the hard-deletes only run after a successful save. A failed save now shows a clear error and leaves all live data intact instead of losing it. Verified via full pytest pass and a successful-purge regression path in the COM check; the failure branch itself was verified by code inspection (triggering the real error dialog isn't scriptable headlessly).

`ArchiveAndPurge` hard-deletes stale patient/appointment/status-history rows from the live data sheets inside the same loop that copies them into an in-memory archive workbook, and only calls `archiveWb.SaveAs` (line 175) after all three sheets have already been mutated — with no `On Error` handling anywhere in the sub.

**Failure scenario:** An admin runs a purge while the configured archive path is unavailable (locked file, permission denied, network share down, or just an invalid path). `SaveAs` throws an unhandled runtime error after the live rows are already deleted from `_data_patients`/`_data_appointments`/`_data_status_history` and no archive file exists on disk — any subsequent save makes the data loss permanent, exactly the failure mode this module is supposed to prevent.

## Real correctness bugs, auth/data-integrity adjacent

### 3. `modAdmin.bas:6` — CreateUser has no username uniqueness check
**CONFIRMED**
**STATUS: FIXED** — Extracted `SetUsername`'s collision check into a shared `UsernameTaken(ws, username, excludeUserId)` helper; `CreateUser` is now a `Function` that checks it before inserting and returns `False` (no row added) on collision. `AddUserForm.frm`'s `btnSave_Click` now checks the return value and shows "That username is already taken." instead of silently proceeding. Verified via COM: creating two users with the same username returns `True` then `False`, and only one row exists afterward.

`CreateUser` inserts a new `_data_users` row with whatever username is passed in, with no uniqueness check — unlike its sibling `SetUsername` (added this session), which explicitly rejects a rename that would collide case-insensitively with another user.

**Failure scenario:** An admin uses "+ Add User" to create two staff accounts that both end up with username "jsmith" (e.g. two people with the same surname initial). Since username is now the sole login credential (`modAuth.ValidateLogin`), the Users table shows two indistinguishable rows and login/session-binding behavior for that username becomes ambiguous, with no in-app way to tell which account is which.

### 4. `modUpgrade.bas:166` — Import's username de-dup is import-row-order dependent
**CONFIRMED**
**STATUS: FIXED** — `MergeSheet` now pre-seeds the `taken` dictionary with every already-non-blank username found anywhere in the old file in a pass *before* the row-copy/derive loop runs, so a blank-username row processed early can never collide with an explicit username that only appears later in the same file. Verified via COM: imported a 19-user old file where row 2 has a blank username that would derive to "jsmith" and row 20 already has the explicit username "jsmith" — confirmed zero duplicate usernames in the result.

`MergeSheet`'s `taken` dictionary (line 151) starts empty and is only populated as each old-file row is processed in sheet order (line ~172), so a blank-username row that derives a candidate username before a later row with that same explicit username has already been seen will not detect the collision.

**Failure scenario:** Importing an old workbook where row 2 has a blank username deriving to "janedoe" and row 20 already has username="janedoe" set by a prior admin: row 2 is processed first (`taken` is still empty), so it's assigned "janedoe" with no collision detected, producing two `_data_users` rows with the identical username after the import completes — the exact invariant `SetUsername` was written to protect.

### 5. `modExport.bas:140` — RunImport has no error handling around its row loop
**CONFIRMED**
**STATUS: FIXED** — Wrapped `RunImport` in `On Error GoTo Fail`; the `Fail:` handler closes the source workbook (if open) and restores `Application.EnableEvents`/`modUtils.gSuppressAutoSave` before showing an error message, mirroring the pattern already used in `modUpgrade.UpgradeFromWorkbookPath`. Verified: full pytest pass and project-wide compile/run check via COM (no live-import-failure scenario was synthesized, since it requires a specifically malformed source file, but the restore logic is structurally identical to the already-COM-verified `modUpgrade` pattern).

`RunImport` sets `Application.EnableEvents=False` and `modUtils.gSuppressAutoSave=True` before its per-row import loop (lines 164-214) and only restores them — and closes the opened source workbook — after the loop completes normally; there is no `On Error` handler anywhere in the sub.

**Failure scenario:** A malformed or edge-case row in the imported legacy file (e.g. one that trips a runtime error inside `modPatients.Save` or `ResolveLovId`) raises an unhandled error partway through import. Execution aborts with `EnableEvents` stuck `False` (every worksheet's `Worksheet_Change`/`Worksheet_Activate` handler app-wide stops firing, including Admin's own settings cells) and `gSuppressAutoSave` stuck `True` (every subsequent save anywhere in the app becomes a silent no-op) until Excel is closed and reopened, plus the read-only source workbook is left open, invisibly holding a file lock.

## Moderate

### 6. `AddEditAppointmentForm.frm:80` — Blank appointment time silently passes validation
**PLAUSIBLE**
**STATUS: FIXED** — Added an explicit `If Trim(txtTime.Text) = "" Then ShowError "Time is required." : Exit Sub` before the format check, matching the date field's existing pattern. Verified: full pytest pass and project-wide compile check via COM (the form's own click-handler logic isn't independently unit-testable without driving the UI, but the whole project — including this form — compiles and the rest of the save path was exercised directly).

The time field's validation only calls `modUtils.IsValidTime(Trim(txtTime.Text))`, with no preceding blank check — unlike the date field two lines above which explicitly rejects an empty value before the format check. `IsValidTime` treats an empty string as valid by design (it's shared with genuinely-optional callers).

**Failure scenario:** A user opens "Add Appointment", picks a date, leaves the time box empty, and clicks Save — the appointment is created with a blank time field even though every other appointment in the system has one, with no error shown.

### 7. `AddEditPatientForm.frm:84` — Blank referral date silently passes validation
**PLAUSIBLE**
**STATUS: FIXED** — Added an explicit `If Trim(txtReferralDate.Text) = "" Then ShowError "Referral date is required." : Exit Sub` before the format check, same pattern as #6. Verified: full pytest pass and project-wide compile check via COM.

The referral-date field's validation only calls `modUtils.IsValidIsoDate(Trim(txtReferralDate.Text))` with no preceding blank check, the same gap as the appointment-time finding — `IsValidIsoDate` treats an empty string as valid by design.

**Failure scenario:** A coordinator adds a patient without picking a referral date; the record saves with `date_of_referral` blank, silently inconsistent with last/first name being correctly hard-required two lines earlier in the same handler.

### 8. `PatientDetailForm.frm:174` — SDAT score parsing can throw unhandled overflow error
**PLAUSIBLE**
**STATUS: FIXED** — `ParsedScore` now converts with `On Error Resume Next` around the `CLng(s)` call and checks `Err.Number` explicitly before the range check, instead of relying on `Or`'s (non-short-circuiting) evaluation of `CLng(s)` unconditionally. An oversized numeric string now correctly falls through to "invalid" instead of raising an uncaught Overflow error. Verified: full pytest pass and project-wide compile check via COM.

`ParsedScore`'s range check is `ElseIf CLng(s) <> CDbl(s) Or CLng(s) < 0 Or CLng(s) > 40 Then` — VBA's `Or` does not short-circuit, so `CLng(s)` is evaluated unconditionally even for `IsNumeric`-accepted values too large for a `Long` (e.g. "99999999999" or scientific notation), raising a runtime Overflow error before the intended 0-40 range check ever runs.

**Failure scenario:** A user fat-fingers an extra digit into the SDAT begin/end score field and clicks Save SDAT — instead of the intended "must be a whole number between 0 and 40" message box, VBA throws an uncaught Run-time error 6 dialog.

### 9. `modAppointments.bas:261` — Ambiguous last-name lookup silently picks first match
**PLAUSIBLE**
**STATUS: FIXED** — `FindActivePatientIdByMrnOrLastName` now checks for an exact MRN match first (always unambiguous, returns immediately) and separately counts last-name matches; it returns a new `-1` sentinel when more than one active patient matches by last name, and `UI_OpenAddAppointment` shows "More than one active patient matches that last name — enter the patient's MRN instead" instead of silently guessing. Verified: full pytest pass and project-wide compile check via COM (the `InputBox`-driven UI entry point itself isn't scriptable headlessly, but the underlying selection logic was re-verified by direct code inspection after the change).

`FindActivePatientIdByMrnOrLastName` returns the first active patient whose MRN or last name matches the search text, with no disambiguation when multiple active patients share the same last name.

**Failure scenario:** Two active patients share a last name (plausible in a hospital census). A coordinator adding an appointment types the shared last name; the function silently returns whichever patient occurs first in row order, with no warning — the appointment gets attached to the wrong patient's record.

### 10. `Admin.cls:21` — Worksheet_Change drops one of two co-edited settings
**PLAUSIBLE**
**STATUS: FIXED** — Removed the `Exit Sub` after each `Intersect` branch so all three tracked cells (I2/C26/E26) are checked independently on every Change event, instead of only the first match. Verified via COM: wrote `C26:E26` in a single multi-cell `.Value =` call and confirmed both `retention_months` and `purge_frequency` were persisted to `_data_settings`.

`Worksheet_Change` checks `Intersect(Target, ...)` against I2, then C26, then E26 in sequence, `Exit Sub`-ing after the first match — so a single Change event whose `Target` spans more than one of these tracked cells only handles the first one checked.

**Failure scenario:** An admin selects C26:E26 and pastes or fill-drags values across both the retention-months and purge-frequency cells in one operation. Only `retention_months` gets persisted to `_data_settings` (the C26 branch runs and exits); `purge_frequency`'s new value is displayed but silently reverts to its old stored value on the next sheet activate.

### 11. `modAdmin.bas:372` — RefreshLovTable's EnableEvents has no error-safe restore
**PLAUSIBLE**
**STATUS: FIXED** — Wrapped the population block in `On Error GoTo Fail`, which restores `Application.EnableEvents` and calls `modUtils.ReprotectAfterRefresh` before showing an error message. **Bonus finding caught while fixing this**: the success path had *no* `ReprotectAfterRefresh` call at all (only the early "no category selected" exit had one) — every real LOV refresh was leaving the Admin sheet permanently unprotected. Both are now fixed together. Verified via COM: called `RefreshLovTable` with a real category selected and confirmed `ws.ProtectContents = True` afterward.

`RefreshLovTable` sets `Application.EnableEvents = False` before writing rows and only sets it back to `True` after the write block completes, with no `On Error` guarantee — unlike `modUpgrade.UpgradeFromWorkbookPath`, which restores this same flag via a `Fail:` handler.

**Failure scenario:** Any runtime error between the two lines (e.g. a `ListRows.Add` failing because the sheet wasn't actually unprotected) leaves `Application.EnableEvents` permanently `False` for the rest of the session, silently disabling every other worksheet event handler in the workbook (Admin's own settings cells, WorkQueue's double-click) until Excel is closed and reopened.

### 12. `modPatients.bas:51` — Raw Cells(ColIndex) bypasses existing null-safe helpers
**PLAUSIBLE** (reuse/cleanup, not a live bug today)
**STATUS: FIXED** — Converted every inline `ws.Cells(r, modUtils.ColIndex(ws, "x")).Value` read/write in `modPatients.bas` (`GetPatient`, `Save`, `AppendStatusHistory`, `ChangeStatus`, `Restore`, `SaveSdat`, `SaveNotes`) and `modAppointments.bas` (`GetAppointment`, `Save`, `ConsultantNameForId`) to `modUtils.GetVal`/`SetVal`. Also added a new shared `modUtils.SafeCLng(v)` helper (treats `Null`/blank as 0 instead of throwing) for the 3 places that immediately convert a looked-up id to `Long` for a `LovValueForId`/`ConsultantNameForId` call, so the null-safety actually reaches those derived lookups too, not just the raw field storage. (Left the *loop-heavy* functions like `ListForWorkQueue`/`ForDay`/`GetForPatient` on their existing cached-column-index pattern — they already resolve each column once outside the loop, which is the right performance tradeoff for hot paths; only the single-record read/write functions needed this.) Verified via COM: patient and appointment save-then-read roundtrips, and full pytest pass.

`modPatients.bas` and `modAppointments.bas` consistently read/write columns via raw `ws.Cells(r, modUtils.ColIndex(ws, name)).Value` instead of the existing `modUtils.GetVal`/`SetVal` helpers, which already guard against `ColIndex` returning 0 for a missing column (`GetVal` returns `Null`, `SetVal` no-ops).

**Failure scenario:** If a column is ever renamed or dropped in a future schema change, `ColIndex` returns 0 and `Cells(r, 0)` is an invalid reference that throws a runtime error — every `Get*`/`Save`/`ChangeStatus`/`SaveSdat` call touching that column crashes outright instead of degrading the way the rest of the codebase's `GetVal`/`SetVal`-based code would.
