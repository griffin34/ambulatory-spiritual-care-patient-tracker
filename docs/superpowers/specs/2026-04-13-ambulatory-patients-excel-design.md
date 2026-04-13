# Ambulatory Patient Tracking System — Excel VBA Workbook Design Spec

**Date:** 2026-04-13  
**Status:** Approved  
**Companion spec:** `2026-04-13-ambulatory-patients-design.md`

---

## Overview

A standalone Excel VBA workbook (`.xlsm`) that implements the same patient tracking workflow as the Electron app. It is a true alternative — not a simplified fallback — targeting hospital machines where Excel is available. No installation required beyond copying the file.

Full feature parity is the goal. Known intentional deltas from the Electron app are listed in the Feature Parity section.

---

## Deployment

- Single `.xlsm` file, copied to the user's machine or a shared drive
- Requires Excel (Windows); no admin rights, no additional software
- Data is stored inside the workbook itself (hidden sheets)
- The file IS the database — back up by copying the file

---

## Architecture

### Structure

**Hidden data sheets** (prefixed `_data_`) — one per logical table, never visible to users:

| Sheet | Purpose |
|-------|---------|
| `_data_users` | User accounts |
| `_data_patients` | Patient records |
| `_data_status_history` | Patient status transitions |
| `_data_appointments` | Appointment records |
| `_data_consultants` | Consultant list |
| `_data_lov` | List of Values (referral sources, religions, languages, appt types) |
| `_data_audit` | Audit log |
| `_data_settings` | App configuration (retention period, purge frequency, last purge date) |

Each sheet: headers in row 1, data from row 2 down, auto-incrementing integer IDs in column A. No rows are ever deleted except during an admin-confirmed purge.

**Visible UI sheets** — one per major screen:

| Sheet | Screen |
|-------|--------|
| `WorkQueue` | Patient work queue |
| `Appointments` | Appointments day view |
| `Reports` | Reporting |
| `Admin` | User management, LoV management, purge config |

**VBA modules:**

| Module | Responsibility |
|--------|---------------|
| `modAuth` | Login, session state, password hashing |
| `modSHA256` | Pure-VBA SHA-256 implementation (no .NET dependency) |
| `modPatients` | Patient CRUD, status transitions |
| `modAppointments` | Appointment CRUD, day view data |
| `modAdmin` | User management, LoV management |
| `modReports` | Report queries, chart refresh |
| `modExport` | All export and import operations |
| `modUtils` | Shared helpers (next ID, date formatting, sheet reads/writes) |
| `modPurge` | Purge detection, archive export, hard delete |

**UserForms:**

| Form | Purpose |
|------|---------|
| `LoginForm` | Username/password login |
| `PatientDetailForm` | Patient profile, status history, appointments panel |
| `AddEditPatientForm` | Add or edit patient record |
| `AddEditAppointmentForm` | Add or edit appointment |
| `AddUserForm` | Create user account (admin only) |
| `ResetPasswordForm` | Reset a user's password (admin only) |
| `ImportMappingForm` | Column mapping preview before Electron import |
| `PurgeConfirmForm` | Confirm purge: shows stale record count, archive path picker |

### Session State

Module-level variables in `modAuth` hold the active session:
- `gUserId As Long`
- `gUserName As String`
- `gUserRole As String` — `"admin"` or `"coordinator"`

Cleared in `Workbook_BeforeClose`. Never written to disk.

### On Open

1. All UI sheets hidden
2. `LoginForm` shown
3. On successful login: UI sheets made visible, `WorkQueue` activated
4. Purge check runs (see Purge Policy)

**First run:** If `_data_users` has zero rows, skip `LoginForm` and show `AddUserForm` in first-admin mode instead.

---

## Data Model

Column names match the SQLite schema exactly (enables direct migration export).

### `_data_users`
| Column | Type | Notes |
|--------|------|-------|
| id | Long | Auto-increment |
| name | String | |
| email | String | Unique |
| password_hash | String | SHA-256 hex |
| role | String | `admin` \| `coordinator` |
| is_active | Integer | 0 or 1 |
| created_at | String | ISO timestamp |

### `_data_patients`
| Column | Type | Notes |
|--------|------|-------|
| id | Long | |
| mrn | String | |
| last_name | String | |
| first_name | String | |
| middle_name | String | |
| phone | String | |
| date_of_referral | String | YYYY-MM-DD |
| referral_source_id | Long | FK → `_data_lov` |
| religion_id | Long | FK → `_data_lov` |
| language_id | Long | FK → `_data_lov` |
| current_status | String | `ready_to_schedule` \| `scheduled` \| `dropped` \| `completed` \| `on_hold` |
| is_active | Integer | Soft-delete |
| created_at | String | |

### `_data_status_history`
| Column | Type | Notes |
|--------|------|-------|
| id | Long | |
| patient_id | Long | |
| status | String | |
| changed_by | Long | FK → `_data_users` |
| changed_at | String | ISO timestamp |

Every status transition writes a new row here AND updates `current_status` on the patient row.

### `_data_appointments`
| Column | Type | Notes |
|--------|------|-------|
| id | Long | |
| patient_id | Long | |
| date | String | YYYY-MM-DD |
| time | String | HH:MM |
| type_id | Long | FK → `_data_lov` |
| consultant_id | Long | FK → `_data_consultants` |
| is_last_appointment | Integer | 0 or 1 |
| status | String | `scheduled` \| `completed` \| `no_show` \| `cancelled` |
| notes | String | |
| created_at | String | |

### `_data_consultants`
| Column | Type | Notes |
|--------|------|-------|
| id | Long | |
| name | String | |
| is_active | Integer | |

### `_data_lov`
| Column | Type | Notes |
|--------|------|-------|
| id | Long | |
| category | String | `referral_source` \| `religion` \| `language` \| `appointment_type` |
| value | String | |
| is_active | Integer | |
| sort_order | Integer | Admin-editable integer (no drag-to-reorder) |

### `_data_audit`
| Column | Type | Notes |
|--------|------|-------|
| id | Long | |
| user_id | Long | |
| action | String | e.g. `status_changed`, `appointment_created` |
| entity | String | e.g. `patient`, `appointment` |
| entity_id | Long | |
| timestamp | String | ISO timestamp |

### `_data_settings`
| Key | Default | Notes |
|-----|---------|-------|
| `retention_months` | 12 | Options: 6, 12, 18, 24 |
| `purge_frequency` | `quarterly` | Options: `monthly`, `quarterly`, `biannual`, `yearly` |
| `last_purge_date` | (empty) | ISO date, updated after each completed purge |

---

## Authentication

- Passwords hashed with SHA-256 (pure-VBA implementation in `modSHA256`)
- Login form validates email + password against `_data_users` where `is_active = 1`
- Failed login shows error message; no account lockout in v1
- Admin-only actions (user management, LoV management, purge) check `gUserRole = "admin"` at runtime and hide/disable controls for coordinators

---

## Status Workflow

| Status | Cell Color | Meaning |
|--------|-----------|---------|
| Ready to Schedule | Green (`#C6EFCE`) | New referral, no appointment yet |
| Scheduled | Yellow (`#FFEB9C`) | Appointment exists |
| Completed | Blue (`#9DC3E6`) | Program complete |
| Dropped | Red (`#FFC7CE`) | Patient disengaged |
| On Hold | Grey (`#D9D9D9`) | Temporarily paused |

Applied via conditional formatting on the `current_status` column in the WorkQueue sheet. Status transitions are unrestricted (any → any) and always recorded in `_data_status_history`.

---

## Screens

### WorkQueue Sheet

- Excel Table (`ListObject`) with columns: Last Name, First Name, MRN, Referral Date, Referral Source, Language, Next Appointment, Status
- Conditional formatting on Status column for color coding
- Filter controls above the table: status filter (dropdown or checkboxes), referral source dropdown, search box (VBA-driven, filters table by name or MRN)
- Stats row: total active patients + count per status (VBA-calculated, refreshed on sheet activate)
- Buttons: `+ Add Patient` (opens `AddEditPatientForm`), `View Patient` (opens `PatientDetailForm` for selected row)
- Double-clicking a row also opens `PatientDetailForm`

### PatientDetailForm

Two-panel UserForm:
- **Left panel:** name, MRN, phone, referral date, referral source, religion, language — with Edit button (opens `AddEditPatientForm` pre-populated). Status badge (label with colored background), Change Status dropdown. Status history list (scrollable listbox: status, changed by, date).
- **Right panel:** chronological list of appointment entries (listbox or frame with labels): date, time, type, consultant, status, last-appointment flag, notes. `+ Add Appointment` button (opens `AddEditAppointmentForm`). Edit button per appointment.

### Appointments Sheet

- Date label + Prev/Next Day buttons + Today button + −14 Days button
- VBA refreshes a table on the sheet showing appointments for the selected date
- Columns: Time, Patient Name, Consultant, Type, Status, Last Appt flag, Notes
- Summary row: count per appointment status for the selected day
- `+ Add Appointment` button

### Reports Sheet

Three stacked sections, each independently configured:

| Report | Input | Output |
|--------|-------|--------|
| Referrals by Source | Date range | Bar chart + table (source, count, %) |
| First Appointments | Date range | Bar chart by week + table (patient, first appt date, consultant) |
| Patients Dropped | Date range | Bar chart by week + table (patient, dropped date, changed by) |

Each section: date range inputs, `Run` button (refreshes chart and table), `Export` button (writes table to `.xlsx`). Charts are native Excel chart objects embedded on the sheet, refreshed by VBA on Run.

### Admin Sheet

Two side-by-side sections:

**User Management:**
- Table of users: name, email, role badge, active status
- Per-row buttons: `Reset PW`, `Deactivate` / `Activate`
- `+ Add User` button (admin sets initial password)
- Coordinator users see this section as read-only (no buttons)

**List of Values:**
- Dropdown to select category (Referral Sources, Religions, Languages, Consultants, Appointment Types)
- Table showing values for selected category with active/inactive state
- Per-row: Edit (inline), Deactivate/Restore
- `+ Add` input + button at top
- `sort_order` column is directly editable (integer; lower = first in dropdowns)

**Purge Configuration** (below LoV section, admin only):
- Retention period dropdown: 6 / 12 / 18 / 24 months
- Purge frequency dropdown: Monthly / Quarterly / Every 6 Months / Yearly
- Last purge date (read-only display)
- `Run Purge Now` button

---

## Purge Policy

**Detection:** On workbook open, after login, if `gUserRole = "admin"`:
1. Check `last_purge_date + purge_frequency ≤ today`
2. If due, scan `_data_patients` for records where last activity (latest of: last appointment date, last status change date) is older than `today - retention_months`
3. If stale records found, show `PurgeConfirmForm`

**PurgeConfirmForm shows:**
- Count of stale patients
- Archive file path (defaulting to same folder as workbook, e.g. `AmbulatoryPatients_Archive_2026-01.xlsx`)
- Browse button to change path
- Confirm / Cancel buttons
- If admin cancels: `last_purge_date` is NOT updated (will prompt again next open)

**On confirm:**
1. Collect all stale patient IDs
2. Write stale patients + their appointments + their status history rows to archive `.xlsx`
3. Hard-delete those rows from `_data_patients`, `_data_appointments`, `_data_status_history`
4. Update `last_purge_date` to today in `_data_settings`
5. Refresh WorkQueue sheet

---

## Export & Migration

### Exports (available to all roles)
- **Work Queue:** exports current filtered view to `.xlsx`
- **Appointments:** exports selected day's appointments to `.xlsx`
- **Reports:** each report card exports its data table (not the chart) to `.xlsx`

### Migration: Excel → Electron
`Export for Import` button in Admin sheet:
- Writes all active data to a structured `.xlsx` with sheet names and column headers matching the Electron app's import wizard exactly
- Sheets: `patients`, `appointments`, `status_history`, `consultants`, `lov`

### Migration: Electron → Excel
`Import from Electron Export` button in Admin sheet:
1. Opens file picker for an Electron export `.xlsx`
2. Shows `ImportMappingForm` with column preview
3. Prompts: **Replace** (wipe all data sheets and reload) or **Merge** (add new records, skip MRNs already in the workbook)
4. Executes import with a progress indicator

---

## Feature Parity Delta

Intentional differences from the Electron app:

| Feature | Electron | Excel |
|---------|---------|-------|
| Password hashing | bcrypt | SHA-256 (pure VBA) |
| LoV reordering | Drag-to-reorder | Editable `sort_order` integer |
| Status badges | Styled React components | Conditional formatting cell colors |
| Charts | Not applicable | Native Excel chart objects (static until Run) |
| Date strip with dots | Scrollable 16-day strip | Prev/Next buttons only |

---

## Out of Scope (v1)

- Real-time sync between Excel and Electron
- Multi-user simultaneous editing (file locking only)
- Epic integration
- Mobile / tablet layout
