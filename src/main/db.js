const Database = require('better-sqlite3')
const path = require('path')

let _db = null

function openDb(file) {
  if (file) return new Database(file)
  const { app } = require('electron')
  const dbPath = path.join(app.getPath('userData'), 'ambulatory.db')
  return new Database(dbPath)
}

function getDb() {
  if (!_db) _db = openDb()
  return _db
}

function runMigrations(db) {
  const instance = db || getDb()
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
      status TEXT NOT NULL DEFAULT 'scheduled' CHECK(status IN ('scheduled','completed','no_show','cancelled')),
      notes TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS consultants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS list_of_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      value TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER REFERENCES users(id),
      action TEXT NOT NULL,
      entity TEXT NOT NULL,
      entity_id INTEGER,
      timestamp TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `)
}

module.exports = { openDb, getDb, runMigrations }
