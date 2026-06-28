import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import fs from 'fs'
import os from 'os'
import path from 'path'
import { openDb, runMigrations, SCHEMA_VERSION } from '../../src/main/db'

let db
beforeEach(() => {
  db = openDb(':memory:')
  runMigrations(db)
})
afterEach(() => db.close())

const patientCols = (d) => d.pragma('table_info(patients)').map(c => c.name)

it('creates all required tables', () => {
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(r => r.name)
  expect(tables).toContain('users')
  expect(tables).toContain('patients')
  expect(tables).toContain('patient_status_history')
  expect(tables).toContain('appointments')
  expect(tables).toContain('consultants')
  expect(tables).toContain('list_of_values')
  expect(tables).toContain('audit_log')
})

it('enforces unique email on users', () => {
  db.prepare("INSERT INTO users (name, email, password_hash, role) VALUES ('A','a@b.com','x','admin')").run()
  expect(() =>
    db.prepare("INSERT INTO users (name, email, password_hash, role) VALUES ('B','a@b.com','x','admin')").run()
  ).toThrow()
})

it('creates the v1.1 patient columns, app_meta, and records schema_version', () => {
  const cols = patientCols(db)
  for (const c of ['sdat_begin_score', 'sdat_begin_date', 'sdat_end_score', 'sdat_end_date', 'sdat_pct_improvement', 'notes']) {
    expect(cols).toContain(c)
  }
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(r => r.name)
  expect(tables).toContain('app_meta')
  const ver = db.prepare("SELECT value FROM app_meta WHERE key='schema_version'").get()
  expect(ver.value).toBe(String(SCHEMA_VERSION))
})

describe('upgrade path', () => {
  it('migrates a pre-1.1 database in place, preserving data, idempotently', () => {
    // Build an "old" schema lacking the SDAT columns and app_meta, with a row.
    const old = new Database(':memory:')
    old.exec(`CREATE TABLE patients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      last_name TEXT NOT NULL, first_name TEXT NOT NULL,
      current_status TEXT NOT NULL DEFAULT 'ready_to_schedule',
      is_active INTEGER NOT NULL DEFAULT 1
    );`)
    old.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Legacy','Pat')").run()

    runMigrations(old)
    const cols = patientCols(old)
    expect(cols).toContain('sdat_begin_score')
    expect(cols).toContain('notes')
    // Existing row preserved with NULLs for new columns
    const row = old.prepare("SELECT * FROM patients WHERE last_name='Legacy'").get()
    expect(row.first_name).toBe('Pat')
    expect(row.sdat_begin_score).toBeNull()
    // Idempotent: running again is a no-op (no duplicate-column error)
    expect(() => runMigrations(old)).not.toThrow()
    expect(old.prepare('SELECT COUNT(*) n FROM patients').get().n).toBe(1)
    old.close()
  })

  it('writes a timestamped backup of an on-disk DB before upgrading', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ambdb-'))
    const file = path.join(dir, 'ambulatory.db')
    // Seed a pre-1.1 on-disk DB with data
    const old = new Database(file)
    old.exec(`CREATE TABLE patients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      last_name TEXT NOT NULL, first_name TEXT NOT NULL,
      current_status TEXT NOT NULL DEFAULT 'ready_to_schedule',
      is_active INTEGER NOT NULL DEFAULT 1
    );`)
    old.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Legacy','Pat')").run()
    old.close()

    const upgraded = openDb(file) // sets the on-disk path used by the backup
    runMigrations(upgraded)
    upgraded.close()

    const backups = fs.readdirSync(dir).filter(f => f.startsWith('ambulatory.db.bak-'))
    expect(backups.length).toBe(1)
    // Backup is a real copy of the original (still readable, row intact)
    const bak = new Database(path.join(dir, backups[0]))
    expect(bak.prepare("SELECT COUNT(*) n FROM patients").get().n).toBe(1)
    bak.close()

    fs.rmSync(dir, { recursive: true, force: true })
  })
})
