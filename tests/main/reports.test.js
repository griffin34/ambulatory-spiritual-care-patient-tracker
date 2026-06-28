import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db.js'
import { createReportsHandlers } from '../../src/main/ipc/reports.js'

let db, handlers

beforeEach(() => {
  db = openDb(':memory:')
  runMigrations(db)
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
    const userId = db.prepare("INSERT INTO users (name, email, password_hash, role) VALUES ('Nurse Adams', 'nurse@x.com', 'x', 'coordinator') RETURNING id").get().id
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

// ── reports:sdatImprovement ───────────────────────────────────────────────

describe('reports:sdatImprovement', () => {
  const addPatient = (last, fields) => {
    const cols = Object.keys(fields)
    const sql = `INSERT INTO patients (last_name, first_name, ${cols.join(', ')}) VALUES (?, ?, ${cols.map(() => '?').join(', ')}) RETURNING id`
    return db.prepare(sql).get(last, 'Test', ...cols.map(c => fields[c])).id
  }

  it('includes patients with both scores whose ending SDAT date is in range, with correct pct', () => {
    // pct_improvement is read from the stored column (computed by patients.js
    // when the scores were saved), not recalculated by the report.
    addPatient('Smith', { sdat_begin_score: 40, sdat_begin_date: '2026-01-10', sdat_end_score: 20, sdat_end_date: '2026-06-10', sdat_pct_improvement: 50.0 })
    const result = handlers['reports:sdatImprovement'](null, { from: '2026-06-01', to: '2026-06-30' })
    expect(result).toHaveLength(1)
    expect(result[0].last_name).toBe('Smith')
    expect(result[0].begin_score).toBe(40)
    expect(result[0].end_score).toBe(20)
    expect(result[0].pct_improvement).toBe(50.0)
  })

  it('filters only on the ending date — begin date may be outside the range', () => {
    addPatient('Early', { sdat_begin_score: 30, sdat_begin_date: '2024-02-01', sdat_end_score: 15, sdat_end_date: '2026-06-15', sdat_pct_improvement: 50.0 })
    const result = handlers['reports:sdatImprovement'](null, { from: '2026-06-01', to: '2026-06-30' })
    expect(result).toHaveLength(1)
    expect(result[0].last_name).toBe('Early')
  })

  it('returns null pct_improvement when begin score is 0 (divide-by-zero guard)', () => {
    addPatient('Zero', { sdat_begin_score: 0, sdat_begin_date: '2026-01-01', sdat_end_score: 0, sdat_end_date: '2026-06-05' })
    const result = handlers['reports:sdatImprovement'](null, { from: '2026-06-01', to: '2026-06-30' })
    expect(result).toHaveLength(1)
    expect(result[0].pct_improvement).toBeNull()
  })

  it('excludes patients missing an end score or end date', () => {
    addPatient('NoEnd', { sdat_begin_score: 30, sdat_begin_date: '2026-06-01' })
    addPatient('NoEndDate', { sdat_begin_score: 30, sdat_end_score: 10 })
    const result = handlers['reports:sdatImprovement'](null, { from: '2026-06-01', to: '2026-06-30' })
    expect(result).toHaveLength(0)
  })

  it('excludes patients whose ending date is outside the range', () => {
    addPatient('Outside', { sdat_begin_score: 30, sdat_begin_date: '2026-01-01', sdat_end_score: 10, sdat_end_date: '2025-12-31' })
    const result = handlers['reports:sdatImprovement'](null, { from: '2026-06-01', to: '2026-06-30' })
    expect(result).toHaveLength(0)
  })

  it('orders results by last name', () => {
    addPatient('Zeta', { sdat_begin_score: 20, sdat_end_score: 10, sdat_end_date: '2026-06-10' })
    addPatient('Alpha', { sdat_begin_score: 20, sdat_end_score: 10, sdat_end_date: '2026-06-12' })
    const result = handlers['reports:sdatImprovement'](null, { from: '2026-06-01', to: '2026-06-30' })
    expect(result.map(r => r.last_name)).toEqual(['Alpha', 'Zeta'])
  })
})
