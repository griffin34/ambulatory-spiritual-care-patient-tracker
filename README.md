# Ambulatory Patient Tracker

A patient tracking app for a hospital spiritual care / chaplaincy team's Ambulatory Scheduling Coordinators. It lives alongside Epic (the hospital EHR) and tracks appointments that Epic can silently drop, manages each patient through a defined workflow, and produces reports on referrals, first appointments, and patient drops.

## Why this exists

Epic doesn't reliably preserve ambulatory spiritual care appointments. This tool gives coordinators a place to own that data: track where each patient is in the process, log every appointment, and pull reports without touching Epic.

## Two flavors

**Electron app** (primary) -- a self-contained `.exe` that runs on locked-down Windows hospital PCs with no installation required. React frontend, SQLite database, bundled Chromium.

**Excel VBA workbook** (companion) -- a standalone `.xlsm` file for any machine that has Excel. Same data model, same workflow, same reports. The file itself is the database.

Both can import/export data from each other.

## What it does

- **Work queue** -- filterable table of all active patients with color-coded status badges (Ready to Schedule / Scheduled / Completed / Dropped / On Hold), search by name or MRN, and quick stats at the top
- **Patient detail** -- full profile, status history timeline, and appointment list all on one screen
- **Appointments day view** -- day-by-day navigation with a scrollable date strip, concurrent appointments shown side by side
- **Reports** -- three independently configured reports (Referrals by Source, First Appointments, Patients Dropped), each with date range inputs, a bar chart, and an Export to Excel button
- **Admin panel** -- user management, list-of-values management (referral sources, religions, languages, consultants, appointment types), and data retention settings
- **Historical import** -- import existing coordinator Excel workbooks into the system

## Tech stack

| Layer | What |
|-------|------|
| Shell | Electron |
| UI | React 19, React Router, Vite |
| Database | better-sqlite3 (SQLite, single `.db` file) |
| Auth | bcryptjs password hashing, in-memory session tokens |
| Excel | SheetJS (xlsx) for import and export |

## Getting started

```bash
npm install
npm run dev
```

First launch seeds the database and prompts you to create the first admin account.

## Building

```bash
npm run build
```

Outputs a self-contained `.exe` (Windows) or `.dmg` (Mac) via electron-builder. CI runs both on every push to `main` and uploads the artifacts.

## Running tests

```bash
npm test
```

## Data and backups

The database lives at `%APPDATA%\AmbulatoryPatients\` as a single `.db` file. Back it up by copying that file.

Data retention is configurable by admins (6, 12, 18, or 24 months). When a purge is due, the app prompts the admin, exports stale records to a dated archive `.xlsx`, then removes them from the database.

## Access control

Two roles: **Admin** and **Coordinator**. Admins create and manage accounts -- there's no self-registration. Session tokens stay in memory only and are never written to disk.

## License

[GNU General Public License v3.0](LICENSE). Any distribution of modified versions must release the source under the same license and preserve the attribution notice in [NOTICE](NOTICE).
