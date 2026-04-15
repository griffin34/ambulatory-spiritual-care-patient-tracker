# Historical Data Import — Design Spec

**Date:** 2026-04-14
**Status:** Approved

---

## Overview

Extend the import capability to support full historical data: patients and their appointment records. The same `.xlsx` template file works for both the Electron app and the future Excel VBA workbook.

---

## Template Format

Single sheet named `patients_and_appointments`. One row per appointment. Patients with multiple appointments have one row per appointment with patient fields repeated. Patients with no appointments have one row with blank appointment columns.

### Columns

| Column | Required | Notes |
|--------|----------|-------|
| `last_name` | Yes | |
| `first_name` | Yes | |
| `middle_name` | No | |
| `mrn` | No | |
| `phone` | No | |
| `date_of_referral` | No | YYYY-MM-DD |
| `referral_source` | No | Text — case-insensitive match to LoV; null if no match |
| `religion` | No | Text — case-insensitive match to LoV; null if no match |
| `language` | No | Text — case-insensitive match to LoV; null if no match |
| `current_status` | No | One of: `ready_to_schedule`, `scheduled`, `completed`, `dropped`, `on_hold`. Defaults to `ready_to_schedule` |
| `appt_date` | No | YYYY-MM-DD — leave blank for patient-only rows |
| `appt_time` | No | HH:MM — leave blank for patient-only rows |
| `appt_type` | No | Text — case-insensitive match to LoV; null if no match |
| `consultant` | No | Text — case-insensitive name match to consultants table; null if no match |
| `appt_status` | No | `scheduled`, `completed`, `no_show`, `cancelled`, `rescheduled`. Defaults to `scheduled` |
| `is_last_appointment` | No | `yes` or `no`. Defaults to `no` |
| `notes` | No | Free text |

### Template File

`docs/patient_import_template.xlsx` — pre-built with headers and one example row. Shipped with the app and made available for download from the Import screen.

---

## Import Logic (Electron)

New IPC handler: `excel:importHistorical`

Processes all rows in a single DB transaction:

1. **Parse** the `patients_and_appointments` sheet from the uploaded file
2. **Group rows by patient** — keyed by MRN (if present) or `last_name + first_name` (case-insensitive)
3. **Per patient:**
   - If MRN already exists in the DB → skip all rows for this patient (count as skipped)
   - Otherwise create the patient using fields from the first row encountered
   - Resolve LoV text values (referral_source, religion, language) by case-insensitive match → null if not found
   - Take `current_status` from the last row for this patient; default to `ready_to_schedule` if blank/invalid
   - Write one `patient_status_history` entry with the resolved status; `changed_by` is null (system import)
4. **Per appointment row** (rows where `appt_date` is non-blank):
   - Resolve `appt_type` → `type_id` by case-insensitive LoV match; null if not found
   - Resolve `consultant` → `consultant_id` by case-insensitive name match; null if not found
   - Resolve `appt_status`; default to `scheduled` if blank/invalid
   - Resolve `is_last_appointment`: `yes` → 1, anything else → 0
   - Insert appointment record linked to the newly created patient
5. **Return** `{ patients_imported, patients_skipped, appointments_imported }`

### Error Handling

- Rows missing both `last_name` and `first_name` are silently skipped
- Unknown LoV/consultant values produce null fields (no error)
- Duplicate MRNs produce a skipped count (no error, no partial import)
- Any DB error rolls back the entire transaction and returns the error message

---

## UI Changes (Electron)

The existing Import screen currently shows a patient-only import flow. Changes:

- Add a second import mode: **"Full Historical Import"**
- User selects the `patients_and_appointments` template file
- After parse, show a preview: row count, patient count detected, appointment count detected
- On confirm, call `excel:importHistorical` and show result summary: `X patients imported, Y skipped (already exist), Z appointments imported`
- Add a **"Download Template"** button that saves `patient_import_template.xlsx` to the user's Downloads folder

---

## Template File Generation

A script (or IPC handler `excel:generateImportTemplate`) writes the template `.xlsx`:
- Sheet: `patients_and_appointments`
- Row 1: column headers (exact names as listed above)
- Row 2: one example row with plausible fake data
- File saved to `docs/patient_import_template.xlsx` in the repo (checked in) and also made available via the Download Template button at runtime

---

## Excel VBA Workbook (future)

When the Excel VBA workbook is built, `modExport` gets an **"Import Historical Data"** button in the Admin sheet (separate from the existing "Import from Electron Export" button). It reads the same flat `patients_and_appointments` sheet and applies equivalent logic in VBA:
- Same deduplication (MRN → last+first fallback)
- Same LoV case-insensitive resolution → skip if no match
- Same consultant name resolution → skip if no match
- Same status history entry on import

The template file is identical — a user fills it out once and can load it into either app.

---

## Out of Scope

- Auto-creating LoV values that don't exist
- Auto-creating consultants that don't exist
- Status history replay (only one history entry is created per imported patient)
- Merge mode (duplicate MRNs are skipped, not merged)
