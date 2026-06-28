// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

const Database = require('better-sqlite3')
const fs = require('fs')
const path = require('path')

// Schema version is bumped whenever runMigrations adds/changes structure.
// It gates the one-time pre-migration backup so existing data is never lost.
const SCHEMA_VERSION = 3

let _db = null
// Absolute path of the on-disk DB (null for in-memory/test databases). Used by
// the pre-migration backup so it can copy the real file before mutating it.
let _dbFilePath = null

function openDb(file) {
  if (file) {
    const db = new Database(file)
    db.pragma('foreign_keys = ON')
    _dbFilePath = file === ':memory:' ? null : path.resolve(file)
    return db
  }
  const { app } = require('electron')
  const dbPath = path.join(app.getPath('userData'), 'ambulatory.db')
  const db = new Database(dbPath)
  db.pragma('foreign_keys = ON')
  _dbFilePath = dbPath
  return db
}

// Copy the on-disk DB to a timestamped .bak before an upgrade migration runs,
// retaining the most recent few. No-op for in-memory/test DBs or fresh installs.
function backupBeforeUpgrade(fromVersion) {
  if (!_dbFilePath || !fs.existsSync(_dbFilePath)) return
  const stamp = new Date().toISOString().replace(/[:T]/g, '').slice(0, 15) // YYYYMMDD-HHMMSS-ish
  const backup = `${_dbFilePath}.bak-${fromVersion}-${stamp}`
  fs.copyFileSync(_dbFilePath, backup)

  // Prune to the 3 most recent backups
  const dir = path.dirname(_dbFilePath)
  const base = path.basename(_dbFilePath)
  const backups = fs.readdirSync(dir)
    .filter(f => f.startsWith(`${base}.bak-`))
    .sort()
  for (const old of backups.slice(0, Math.max(0, backups.length - 3))) {
    try { fs.unlinkSync(path.join(dir, old)) } catch { /* best effort */ }
  }
}

function getDb() {
  if (!_db) _db = openDb()
  return _db
}

function runMigrations(db) {
  const instance = db || getDb()

  // Determine the stored schema version and whether this is an existing install,
  // so we can take a one-time backup before mutating real data on upgrade.
  const hasTable = (name) =>
    !!instance.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(name)
  const hasPatients = hasTable('patients')
  let storedVersion
  if (hasTable('app_meta')) {
    const row = instance.prepare("SELECT value FROM app_meta WHERE key='schema_version'").get()
    storedVersion = row ? parseInt(row.value, 10) : (hasPatients ? 1 : 0)
  } else {
    // No app_meta: pre-1.1 DB with data counts as v1; a brand-new DB counts as v0.
    storedVersion = hasPatients ? 1 : 0
  }
  if (hasPatients && storedVersion < SCHEMA_VERSION) {
    backupBeforeUpgrade(storedVersion)
  }

  // Migration: add is_chaplain column to consultants
  const consultantCols = instance.pragma('table_info(consultants)').map(c => c.name)
  if (consultantCols.length > 0 && !consultantCols.includes('is_chaplain')) {
    instance.exec(`ALTER TABLE consultants ADD COLUMN is_chaplain INTEGER NOT NULL DEFAULT 0`)
  }

  // Migration: expand appointments.status CHECK to include 'rescheduled'
  const apptSql = instance.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='appointments'").get()
  if (apptSql && apptSql.sql && !apptSql.sql.includes("'rescheduled'")) {
    instance.exec(`
      PRAGMA foreign_keys = OFF;
      ALTER TABLE appointments RENAME TO _appointments_old;
      CREATE TABLE appointments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL REFERENCES patients(id),
        date TEXT NOT NULL,
        time TEXT NOT NULL,
        type_id INTEGER REFERENCES list_of_values(id),
        consultant_id INTEGER REFERENCES consultants(id),
        is_last_appointment INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'scheduled' CHECK(status IN ('scheduled','completed','no_show','cancelled','rescheduled')),
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      INSERT INTO appointments SELECT * FROM _appointments_old;
      DROP TABLE _appointments_old;
      PRAGMA foreign_keys = ON;
    `)
  }

  // v1.1 structural changes wrapped in a transaction so a failure rolls back
  // cleanly. (The appointments rebuild above toggles PRAGMA foreign_keys and
  // must stay outside a transaction.)
  const applyV11 = instance.transaction(() => {
    // Migration: add SDAT score/date + notes columns to patients (additive, nullable).
    // Guarded per-column so re-running on an upgraded DB is a no-op.
    const patientCols = instance.pragma('table_info(patients)').map(c => c.name)
    if (patientCols.length > 0) {
      const addCol = (name, ddl) => {
        if (!patientCols.includes(name)) instance.exec(`ALTER TABLE patients ADD COLUMN ${ddl}`)
      }
      addCol('sdat_begin_score', 'sdat_begin_score INTEGER')
      addCol('sdat_begin_date', 'sdat_begin_date TEXT')
      addCol('sdat_end_score', 'sdat_end_score INTEGER')
      addCol('sdat_end_date', 'sdat_end_date TEXT')
      addCol('notes', 'notes TEXT')
      // Stored (not recomputed per-report) percent improvement; kept in sync by
      // patients.js whenever either SDAT score changes.
      addCol('sdat_pct_improvement', 'sdat_pct_improvement REAL')
    }

    instance.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK(role IN ('admin','coordinator')),
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS patients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mrn TEXT,
      last_name TEXT NOT NULL,
      first_name TEXT NOT NULL,
      middle_name TEXT,
      phone TEXT,
      date_of_referral TEXT,
      referral_source_id INTEGER REFERENCES list_of_values(id),
      religion_id INTEGER REFERENCES list_of_values(id),
      language_id INTEGER REFERENCES list_of_values(id),
      current_status TEXT NOT NULL DEFAULT 'ready_to_schedule',
      is_active INTEGER NOT NULL DEFAULT 1,
      sdat_begin_score INTEGER,
      sdat_begin_date TEXT,
      sdat_end_score INTEGER,
      sdat_end_date TEXT,
      sdat_pct_improvement REAL,
      notes TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS patient_status_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      status TEXT NOT NULL,
      changed_by INTEGER REFERENCES users(id),
      changed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS appointments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      date TEXT NOT NULL,
      time TEXT NOT NULL,
      type_id INTEGER REFERENCES list_of_values(id),
      consultant_id INTEGER REFERENCES consultants(id),
      is_last_appointment INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'scheduled' CHECK(status IN ('scheduled','completed','no_show','cancelled','rescheduled')),
      notes TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS consultants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      is_chaplain INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS list_of_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      value TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0,
      UNIQUE(category, value)
    );
    CREATE TABLE IF NOT EXISTS audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER REFERENCES users(id),
      action TEXT NOT NULL,
      entity TEXT NOT NULL,
      entity_id INTEGER,
      timestamp TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS app_meta (
      key TEXT PRIMARY KEY,
      value TEXT
    );
  `)

    // Record the schema version we've migrated to.
    instance.prepare(`
      INSERT INTO app_meta (key, value) VALUES ('schema_version', ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(String(SCHEMA_VERSION))
  })

  applyV11()
}

module.exports = { openDb, getDb, runMigrations, SCHEMA_VERSION }
