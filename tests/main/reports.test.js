import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { createReportsHandlers } from '../../src/main/ipc/reports.js'

let db, handlers

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')

  db.exec(`
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL
    );

    CREATE TABLE list_of_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      value TEXT NOT NULL
    );

    CREATE TABLE consultants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE patients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      last_name TEXT NOT NULL,
      first_name TEXT NOT NULL,
      mrn TEXT,
      date_of_referral TEXT,
      referral_source_id INTEGER REFERENCES list_of_values(id),
      current_status TEXT NOT NULL DEFAULT 'ready_to_schedule',
      is_active INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE patient_status_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      status TEXT NOT NULL,
      changed_at TEXT NOT NULL DEFAULT (datetime('now')),
      changed_by INTEGER REFERENCES users(id)
    );

    CREATE TABLE appointments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      date TEXT NOT NULL,
      time TEXT NOT NULL,
      consultant_id INTEGER REFERENCES consultants(id),
      status TEXT NOT NULL DEFAULT 'scheduled'
    );
  `)

  handlers = createReportsHandlers(db)
})

afterEach(() => db.close())

// ── reports:referralsBySource ──────────────────────────────────────────────

describe('reports:referralsBySource', () => {
  it('returns counts grouped by source within date range', () => {
    const sourceId = db.prepare("INSERT INTO list_of_values (category, value) VALUES ('referral_source', 'GP') RETURNING id").get().id
    db.prepare("INSERT INTO patients (last_name, first_name, date_of_referral, referral_source_id) VALUES (?, ?, ?, ?)").run('Smith', 'John', '2026-01-15', sourceId)
    db.prepare("INSERT INTO patients (last_name, first_name, date_of_referral, referral_source_id) VALUES (?, ?, ?, ?)").run('Jones', 'Jane', '2026-01-20', sourceId)

    const result = handlers['reports:referralsBySource'](null, { from: '2026-01-01', to: '2026-01-31' })
    expect(result).toHaveLength(1)
    expect(result[0].source).toBe('GP')
    expect(result[0].count).toBe(2)
  })

  it('returns null source for patients with no referral source', () => {
    db.prepare("INSERT INTO patients (last_name, first_name, date_of_referral) VALUES (?, ?, ?)").run('NoSource', 'Alice', '2026-02-10')

    const result = handlers['reports:referralsBySource'](null, { from: '2026-02-01', to: '2026-02-28' })
    expect(result).toHaveLength(1)
    expect(result[0].source).toBeNull()
    expect(result[0].count).toBe(1)
  })

  it('returns empty array when no patients in date range', () => {
    db.prepare("INSERT INTO patients (last_name, first_name, date_of_referral) VALUES (?, ?, ?)").run('Outside', 'Range', '2025-01-01')

    const result = handlers['reports:referralsBySource'](null, { from: '2026-01-01', to: '2026-01-31' })
    expect(result).toHaveLength(0)
  })

  it('sorts results descending by count', () => {
    const src1 = db.prepare("INSERT INTO list_of_values (category, value) VALUES ('referral_source', 'Hospital') RETURNING id").get().id
    const src2 = db.prepare("INSERT INTO list_of_values (category, value) VALUES ('referral_source', 'GP') RETURNING id").get().id
    db.prepare("INSERT INTO patients (last_name, first_name, date_of_referral, referral_source_id) VALUES (?, ?, ?, ?)").run('A', 'A', '2026-03-01', src1)
    db.prepare("INSERT INTO patients (last_name, first_name, date_of_referral, referral_source_id) VALUES (?, ?, ?, ?)").run('B', 'B', '2026-03-02', src2)
    db.prepare("INSERT INTO patients (last_name, first_name, date_of_referral, referral_source_id) VALUES (?, ?, ?, ?)").run('C', 'C', '2026-03-03', src2)

    const result = handlers['reports:referralsBySource'](null, { from: '2026-03-01', to: '2026-03-31' })
    expect(result[0].source).toBe('GP')
    expect(result[0].count).toBe(2)
    expect(result[1].source).toBe('Hospital')
    expect(result[1].count).toBe(1)
  })
})

// ── reports:firstAppointments ─────────────────────────────────────────────

describe('reports:firstAppointments', () => {
  it('returns patients whose first appointment falls within range', () => {
    const consultantId = db.prepare("INSERT INTO consultants (name) VALUES ('Dr. Brown') RETURNING id").get().id
    const patientId = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Taylor', 'Bob') RETURNING id").get().id
    db.prepare("INSERT INTO appointments (patient_id, date, time, status, consultant_id) VALUES (?, ?, ?, ?, ?)").run(patientId, '2026-04-10', '09:00', 'completed', consultantId)
    db.prepare("INSERT INTO appointments (patient_id, date, time, status, consultant_id) VALUES (?, ?, ?, ?, ?)").run(patientId, '2026-04-20', '10:00', 'scheduled', consultantId)

    const result = handlers['reports:firstAppointments'](null, { from: '2026-04-01', to: '2026-04-30' })
    expect(result).toHaveLength(1)
    expect(result[0].last_name).toBe('Taylor')
    expect(result[0].first_appt_date).toBe('2026-04-10')
    expect(result[0].consultant_name).toBe('Dr. Brown')
  })

  it('excludes cancelled appointments when determining first appointment', () => {
    const patientId = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('White', 'Carol') RETURNING id").get().id
    // Cancelled appointment before the scheduled one — should not count
    db.prepare("INSERT INTO appointments (patient_id, date, time, status) VALUES (?, ?, ?, ?)").run(patientId, '2026-04-05', '08:00', 'cancelled')
    db.prepare("INSERT INTO appointments (patient_id, date, time, status) VALUES (?, ?, ?, ?)").run(patientId, '2026-04-15', '09:00', 'scheduled')

    const result = handlers['reports:firstAppointments'](null, { from: '2026-04-01', to: '2026-04-30' })
    expect(result).toHaveLength(1)
    expect(result[0].first_appt_date).toBe('2026-04-15')
  })

  it('returns empty array when no first appointments in range', () => {
    const patientId = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Black', 'Dan') RETURNING id").get().id
    db.prepare("INSERT INTO appointments (patient_id, date, time, status) VALUES (?, ?, ?, ?)").run(patientId, '2025-12-01', '10:00', 'completed')

    const result = handlers['reports:firstAppointments'](null, { from: '2026-04-01', to: '2026-04-30' })
    expect(result).toHaveLength(0)
  })

  it('sorts results by first_appt_date ascending', () => {
    const p1 = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Alpha', 'A') RETURNING id").get().id
    const p2 = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Beta', 'B') RETURNING id").get().id
    db.prepare("INSERT INTO appointments (patient_id, date, time, status) VALUES (?, ?, ?, ?)").run(p1, '2026-05-20', '10:00', 'scheduled')
    db.prepare("INSERT INTO appointments (patient_id, date, time, status) VALUES (?, ?, ?, ?)").run(p2, '2026-05-10', '09:00', 'scheduled')

    const result = handlers['reports:firstAppointments'](null, { from: '2026-05-01', to: '2026-05-31' })
    expect(result[0].last_name).toBe('Beta')
    expect(result[1].last_name).toBe('Alpha')
  })
})

// ── reports:patientsDropped ───────────────────────────────────────────────

describe('reports:patientsDropped', () => {
  it('returns dropped patients within date range', () => {
    const userId = db.prepare("INSERT INTO users (name) VALUES ('Nurse Adams') RETURNING id").get().id
    const patientId = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Green', 'Eve') RETURNING id").get().id
    db.prepare("INSERT INTO patient_status_history (patient_id, status, changed_at, changed_by) VALUES (?, 'dropped', ?, ?)").run(patientId, '2026-03-15 10:30:00', userId)

    const result = handlers['reports:patientsDropped'](null, { from: '2026-03-01', to: '2026-03-31' })
    expect(result).toHaveLength(1)
    expect(result[0].last_name).toBe('Green')
    expect(result[0].changed_by_name).toBe('Nurse Adams')
  })

  it('does not include non-dropped status changes', () => {
    const patientId = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Brown', 'Frank') RETURNING id").get().id
    db.prepare("INSERT INTO patient_status_history (patient_id, status, changed_at) VALUES (?, 'scheduled', ?)").run(patientId, '2026-03-10 09:00:00')

    const result = handlers['reports:patientsDropped'](null, { from: '2026-03-01', to: '2026-03-31' })
    expect(result).toHaveLength(0)
  })

  it('returns empty array when no patients dropped in range', () => {
    const patientId = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Grey', 'Gina') RETURNING id").get().id
    db.prepare("INSERT INTO patient_status_history (patient_id, status, changed_at) VALUES (?, 'dropped', ?)").run(patientId, '2025-06-01 08:00:00')

    const result = handlers['reports:patientsDropped'](null, { from: '2026-03-01', to: '2026-03-31' })
    expect(result).toHaveLength(0)
  })

  it('sorts results by changed_at descending', () => {
    const p1 = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Earlier', 'A') RETURNING id").get().id
    const p2 = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Later', 'B') RETURNING id").get().id
    db.prepare("INSERT INTO patient_status_history (patient_id, status, changed_at) VALUES (?, 'dropped', ?)").run(p1, '2026-03-05 08:00:00')
    db.prepare("INSERT INTO patient_status_history (patient_id, status, changed_at) VALUES (?, 'dropped', ?)").run(p2, '2026-03-20 14:00:00')

    const result = handlers['reports:patientsDropped'](null, { from: '2026-03-01', to: '2026-03-31' })
    expect(result[0].last_name).toBe('Later')
    expect(result[1].last_name).toBe('Earlier')
  })

  it('returns null changed_by_name when no user recorded', () => {
    const patientId = db.prepare("INSERT INTO patients (last_name, first_name) VALUES ('Unknown', 'User') RETURNING id").get().id
    db.prepare("INSERT INTO patient_status_history (patient_id, status, changed_at, changed_by) VALUES (?, 'dropped', ?, NULL)").run(patientId, '2026-03-12 11:00:00')

    const result = handlers['reports:patientsDropped'](null, { from: '2026-03-01', to: '2026-03-31' })
    expect(result).toHaveLength(1)
    expect(result[0].changed_by_name).toBeNull()
  })
})
