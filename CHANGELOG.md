# Changelog

All notable changes to the Ambulatory Patient Tracker are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/), and this
project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-06-30

### Added
- **SDAT tracking on patients** — beginning and ending SDAT scores (integers 0–40)
  with their dates, and a 256-character notes field. SDAT and Notes each live in
  their own card on the patient's page, editable independently (via a pencil
  icon) without opening the full profile edit form. Entering a score auto-fills
  its date with today's date if one isn't already set.
- **SDAT % improvement** — calculated automatically (lower distress is better)
  and shown live as scores are entered; the result is stored on the patient so
  reports never need to recompute it.
- **SDAT Improvement report** — percent improvement aggregated across patients,
  filtered by the date of the patient's ending (final) SDAT. Shows per-patient
  rows and an overall total (`(Σbegin − Σend) / Σbegin`).
- **Reports control redesign** — one Report selector (defaults to "All Reports",
  or pick a single report), one shared date range, and a single Run button,
  replacing the separate controls each report card used to have. A report with
  no matching data shows "No results found" instead of an empty chart/table.
- **Soft delete & restore** — delete a patient record made in error from its
  detail page; it becomes a "Deleted" record (hidden from the default Work
  Queue, visible under the Deleted filter) and can be restored. Status history
  is preserved.
- **Sortable Work Queue** — click any column heading to sort ascending/descending.
- **Print** — a Print button on the Work Queue, Patient Detail, Appointments, and
  Reports screens. Each is tailored for paper rather than a screenshot of the
  screen: Patient Detail prints as two single portrait pages (patient
  information, then schedule); the day view prints just the selected date and
  its appointments, without the date-picker strip or nav controls; reports
  print the date range as plain text and omit any report that hasn't been run.
- **In-app version label** and a one-time **"What's New"** dialog shown after an
  upgrade.

### Changed
- Admin list-of-values (religions, languages, referral sources, appointment types)
  now display alphabetically (A–Z); patient-profile dropdowns inherit this order.

### Fixed
- Editing a patient profile that had unset referral source / religion / language
  no longer fails (carried over from the prior maintenance release).

### Upgrade notes
- The app is a portable executable; upgrade by running the new build in place of
  the old one. The database lives in your user profile (`%APPDATA%\ambulatory-patients\`
  on Windows) and is **not** touched by replacing the app.
- On first launch of 1.1.0, the database schema is migrated automatically: the new
  SDAT/notes columns are added (existing data preserved) and a timestamped backup
  (`ambulatory.db.bak-*`) is written next to the database before any change.

## [1.0.1] - 2026-06

### Fixed
- Correctness fixes to patient editing, report date handling, and Excel import
  (see commit history).
