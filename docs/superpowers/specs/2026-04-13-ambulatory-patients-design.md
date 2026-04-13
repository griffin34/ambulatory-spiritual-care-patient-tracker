# Ambulatory Patient Tracking System — Design Spec

**Date:** 2026-04-13  
**Status:** Approved  
**Confluence:** https://jasongriffin.atlassian.net/wiki/spaces/~712020db4646bdec034470bdd1ad1bc1e84267/pages/2359297/Ambulatory+Patient+Planning

---

## Overview

A patient tracking system for an Ambulatory Scheduling Coordinator team at a hospital's spiritual care / chaplaincy department. The system serves as a companion to Epic (the hospital EHR), specifically tracking appointments that Epic may delete without notification. It manages patients through a defined workflow, records appointments with spiritual care consultants, and provides reporting on referrals, first appointments, and drops.

---

## Deployment Constraints

- **Target:** Locked-down Windows hospital PCs (no admin rights, no software installation)
- **Solution A (primary):** Electron + React + SQLite — self-contained `.exe`, no installation required, bundled Chromium eliminates browser compatibility risk
- **Solution B (companion):** Excel VBA workbook — same data model, guaranteed fallback for any machine with Excel
- **Users:** Small team of Scheduling Coordinators + Admins
- **Auth:** Admin-managed accounts only; no self-registration

---

## Architecture (Electron App)

**Three layers:**

1. **Shell** — Electron main process manages the window, file system access, and IPC bridge
2. **UI** — React (Vite) frontend communicates with the backend via `ipcRenderer`
3. **Data** — `better-sqlite3` runs synchronously in the main process; single `.db` file at `%APPDATA%\AmbulatoryPatients\`

**Key libraries:**
- `better-sqlite3` — local SQLite database
- `bcrypt` — password hashing
- `xlsx` (SheetJS) — Excel import and export
- `react` + `vite` — UI layer

**First launch:** App seeds the DB and prompts to create the first admin account. The `.db` file persists across app updates and can be backed up by copying one file.

**Auth:** Session token stored in memory only (not on disk). Passwords are bcrypt-hashed in SQLite.

---

## Data Model

### `users`
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | |
| name | TEXT | |
| email | TEXT UNIQUE | |
| password_hash | TEXT | bcrypt |
| role | TEXT | `admin` \| `coordinator` |
| is_active | INTEGER | 0 or 1 |
| created_at | TEXT | ISO timestamp |

### `patients`
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | |
| mrn | TEXT | Medical Record Number |
| last_name | TEXT | |
| first_name | TEXT | |
| middle_name | TEXT | |
| phone | TEXT | |
| date_of_referral | TEXT | |
| referral_source_id | INTEGER | FK → list_of_values |
| religion_id | INTEGER | FK → list_of_values |
| language_id | INTEGER | FK → list_of_values |
| current_status | TEXT | `ready_to_schedule` \| `scheduled` \| `dropped` \| `completed` \| `on_hold` |
| is_active | INTEGER | soft-delete flag |
| created_at | TEXT | |

### `patient_status_history`
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | |
| patient_id | INTEGER | FK → patients |
| status | TEXT | |
| changed_by | INTEGER | FK → users |
| changed_at | TEXT | ISO timestamp |

Every status transition writes a new row here. `patients.current_status` is a denormalized convenience field kept in sync.

### `appointments`
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | |
| patient_id | INTEGER | FK → patients |
| date | TEXT | YYYY-MM-DD |
| time | TEXT | HH:MM |
| type_id | INTEGER | FK → list_of_values (telemed \| video) |
| consultant_id | INTEGER | FK → consultants |
| is_last_appointment | INTEGER | 0 or 1 |
| status | TEXT | `scheduled` \| `completed` \| `no_show` \| `cancelled` |
| notes | TEXT | |
| created_at | TEXT | |

### `consultants`
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | |
| name | TEXT | |
| is_active | INTEGER | |

### `list_of_values`
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | |
| category | TEXT | `referral_source` \| `religion` \| `language` \| `appointment_type` |
| value | TEXT | |
| is_active | INTEGER | soft-delete |
| sort_order | INTEGER | admin-controlled drag ordering |

### `settings`
| Column | Type | Notes |
|--------|------|-------|
| key | TEXT PK | e.g. `retention_months`, `purge_frequency`, `last_purge_date` |
| value | TEXT | |

### `audit_log`
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | |
| user_id | INTEGER | FK → users |
| action | TEXT | e.g. `status_changed`, `appointment_created` |
| entity | TEXT | e.g. `patient`, `appointment` |
| entity_id | INTEGER | |
| timestamp | TEXT | ISO timestamp |

---

## Status Workflow

| Status | Color | Meaning |
|--------|-------|---------|
| Ready to Schedule | Green | New referral, no appointment yet |
| Scheduled | Yellow | Appointment exists in system |
| Completed | Blue | Patient has completed the program |
| Dropped | Red | Patient disengaged or unreachable |
| On Hold | Grey | Temporarily paused |

Status transitions are unrestricted (any → any) but always recorded in `patient_status_history`.

---

## Screens

### 1. Work Queue (default landing)
- Filterable table: name, MRN, referral date, referral source, language, next appointment, color-coded status badge
- Status filter chips + referral source dropdown
- Stats bar: total active + count per status
- Search by name or MRN
- "+ Add Patient" button
- Click row → Patient Detail

### 2. Patient Detail
- Breadcrumb: Work Queue › Patient Name
- Header: name, MRN, religion/language tags, current status badge, "Change Status" dropdown
- Profile card: phone, referral date, referral source, religion, language — with Edit
- Status history timeline: status, who changed it, when
- Appointments panel (right): chronological list of appointment cards showing date, time, type, consultant, status badge, last-appointment flag, notes
- "+ Add Appointment" button

### 3. Appointments Day View
- Arrow navigation (day by day) + Today / -14 Days quick-jump buttons
- Scrollable date strip showing 16+ days with dots for days that have appointments
- Day summary chips: count per appointment status
- List-based layout grouped by time: appointments at the same time slot render as side-by-side cards (scales to 5+ concurrent)
- Each card: patient name, consultant, appointment type tag, last-appointment flag, status badge

### 4. Reports
Three report cards, each independently configured:

| Report | Date Range Input | Chart | Scrollable Table |
|--------|-----------------|-------|-----------------|
| Referrals by Source | Yes | Bar chart by source | Source, count, % |
| First Appointments | Yes | Bar chart by week | Patient, first appt date, consultant |
| Patients Dropped | Yes | Bar chart by week | Patient, dropped date, changed by |

Each card has Run and Export (xlsx) buttons. Table panel is fixed-height and scrollable inline.

### 5. Admin (admin role only)
Two side-by-side panels:

**User Management:**
- User rows: avatar, name, email, role badge (Admin/Coordinator), active status dot
- Actions: Reset Password, Deactivate / Activate
- "+ Add User" creates account (admin sets initial password)

**List of Values:**
- Tabs: Referral Sources, Religions, Languages, Consultants, Appointment Types
- Per tab: add new value inline, drag-to-reorder, edit, soft-delete (struck-through with restore option)
- LoV changes take effect immediately in all dropdowns

**Data Retention Settings:**
- Retention period dropdown: 6 / 12 / 18 / 24 months
- Purge frequency dropdown: Monthly / Quarterly / Every 6 Months / Yearly
- Last purge date (read-only)
- "Run Purge Now" button triggers purge flow immediately regardless of schedule

---

## Reporting Queries

**Referrals by source:** `patients` filtered by `date_of_referral` in range, grouped by `referral_source_id`

**First appointments:** `appointments` joined to `patients`, filtered to each patient's `MIN(date)` falling within range

**Patients dropped:** `patient_status_history` where `status = 'dropped'` and `changed_at` in range

---

## Excel Features

**Import:** SheetJS parses existing coordinator Excel workbook in Electron main process, bulk-inserts into SQLite. Column mapping UI shown before import.

**Export:** Available from Work Queue, Appointments Day View, and each Report card. Writes formatted `.xlsx` to user-selected path via Electron's `showSaveDialog`.

---

## Data Retention

**Retention period:** Configurable by admin (6, 12, 18, or 24 months). Default: 12 months. Stored in a `settings` table (`key`, `value`).

**Purge frequency:** Configurable by admin (monthly, quarterly, every 6 months, yearly). Default: quarterly. Also stored in `settings`.

**Stale detection:** A patient is stale when their last activity — the later of their most recent appointment date and most recent status change date — is older than `today - retention_months`.

**Trigger:** On app launch, after login, if the logged-in user is an admin and `last_purge_date + purge_frequency ≤ today` and stale records exist, the app prompts the admin before doing anything. If the admin declines, `last_purge_date` is not updated.

**On confirm:** All stale patient records (plus their appointments and status history) are exported to a dated archive `.xlsx` file at a path the admin selects, then hard-deleted from the database. `last_purge_date` is updated to today.

**`settings` table:**
| key | default |
|-----|---------|
| `retention_months` | `12` |
| `purge_frequency` | `quarterly` |
| `last_purge_date` | (empty until first purge) |

---

## Out of Scope (v1)

- Integration with Epic (read or write)
- Email or SMS notifications
- Mobile / tablet layout
- Multi-location support
