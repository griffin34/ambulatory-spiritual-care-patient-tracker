import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db'
import { createPatientHandlers } from '../../src/main/ipc/patients'

let db, h
beforeEach(() => {
  db = openDb(':memory:')
  runMigrations(db)
  h = createPatientHandlers(db)
})
afterEach(() => db.close())

it('creates a patient', async () => {
  const p = await h.createPatient({ last_name: 'Smith', first_name: 'John', userId: 1 })
  expect(p.id).toBeTruthy()
  expect(p.current_status).toBe('ready_to_schedule')
})

it('records initial status in history', async () => {
  const p = await h.createPatient({ last_name: 'Smith', first_name: 'John', userId: 1 })
  const history = db.prepare('SELECT * FROM patient_status_history WHERE patient_id = ?').all(p.id)
  expect(history).toHaveLength(1)
  expect(history[0].status).toBe('ready_to_schedule')
})

it('transitions patient status and records history', async () => {
  const p = await h.createPatient({ last_name: 'Smith', first_name: 'John', userId: 1 })
  await h.transitionStatus({ patientId: p.id, status: 'scheduled', userId: 1 })
  const updated = await h.getPatient({ id: p.id })
  expect(updated.current_status).toBe('scheduled')
  const history = db.prepare('SELECT * FROM patient_status_history WHERE patient_id = ?').all(p.id)
  expect(history).toHaveLength(2)
})

it('lists only active patients', async () => {
  await h.createPatient({ last_name: 'Active', first_name: 'A', userId: 1 })
  const p2 = await h.createPatient({ last_name: 'Inactive', first_name: 'B', userId: 1 })
  db.prepare('UPDATE patients SET is_active = 0 WHERE id = ?').run(p2.id)
  const list = await h.listPatients({})
  expect(list).toHaveLength(1)
})

// ── SDAT scores + notes ────────────────────────────────────────────────────

it('persists SDAT scores, dates, and notes on create', async () => {
  const p = await h.createPatient({
    last_name: 'Smith', first_name: 'John',
    sdat_begin_score: 40, sdat_begin_date: '2026-01-10',
    sdat_end_score: 0, sdat_end_date: '2026-06-10', notes: 'hello'
  })
  const row = db.prepare('SELECT * FROM patients WHERE id = ?').get(p.id)
  expect(row.sdat_begin_score).toBe(40)
  expect(row.sdat_begin_date).toBe('2026-01-10')
  expect(row.sdat_end_score).toBe(0) // 0 is valid and must not be nulled
  expect(row.notes).toBe('hello')
})

it('rejects SDAT scores outside 0–40', async () => {
  await expect(h.createPatient({ last_name: 'X', first_name: 'Y', sdat_begin_score: 41 })).rejects.toThrow()
  await expect(h.createPatient({ last_name: 'X', first_name: 'Y', sdat_end_score: -1 })).rejects.toThrow()
})

it('rejects notes longer than 256 characters', async () => {
  await expect(h.createPatient({ last_name: 'X', first_name: 'Y', notes: 'a'.repeat(257) })).rejects.toThrow()
  const ok = await h.createPatient({ last_name: 'X', first_name: 'Y', notes: 'a'.repeat(256) })
  expect(ok.id).toBeTruthy()
})

it('coerces empty SDAT/notes to null', async () => {
  const p = await h.createPatient({ last_name: 'X', first_name: 'Y', sdat_begin_score: '', notes: '' })
  const row = db.prepare('SELECT * FROM patients WHERE id = ?').get(p.id)
  expect(row.sdat_begin_score).toBeNull()
  expect(row.notes).toBeNull()
})

it('updates SDAT fields including score 0, and validates range', async () => {
  const p = await h.createPatient({ last_name: 'Smith', first_name: 'John' })
  await h.updatePatient({ id: p.id, sdat_begin_score: 30, sdat_end_score: 0, notes: 'note' })
  let row = db.prepare('SELECT * FROM patients WHERE id = ?').get(p.id)
  expect(row.sdat_begin_score).toBe(30)
  expect(row.sdat_end_score).toBe(0)
  expect(row.notes).toBe('note')
  await expect(h.updatePatient({ id: p.id, sdat_begin_score: 41 })).rejects.toThrow()
})

// ── stored SDAT % improvement ──────────────────────────────────────────────

it('computes and stores pct_improvement on create when both scores are present', async () => {
  const p = await h.createPatient({ last_name: 'A', first_name: 'B', sdat_begin_score: 40, sdat_end_score: 20 })
  const row = db.prepare('SELECT sdat_pct_improvement FROM patients WHERE id = ?').get(p.id)
  expect(row.sdat_pct_improvement).toBe(50)
})

it('leaves pct_improvement null when only one score is present, or begin is 0', async () => {
  const p1 = await h.createPatient({ last_name: 'A', first_name: 'B', sdat_begin_score: 40 })
  expect(db.prepare('SELECT sdat_pct_improvement FROM patients WHERE id = ?').get(p1.id).sdat_pct_improvement).toBeNull()
  const p2 = await h.createPatient({ last_name: 'A', first_name: 'B', sdat_begin_score: 0, sdat_end_score: 0 })
  expect(db.prepare('SELECT sdat_pct_improvement FROM patients WHERE id = ?').get(p2.id).sdat_pct_improvement).toBeNull()
})

it('recomputes pct_improvement on update, merging with the score already stored', async () => {
  const p = await h.createPatient({ last_name: 'A', first_name: 'B', sdat_begin_score: 40 })
  // Only the end score is sent — begin score must come from the existing row.
  await h.updatePatient({ id: p.id, sdat_end_score: 30 })
  const row = db.prepare('SELECT sdat_pct_improvement FROM patients WHERE id = ?').get(p.id)
  expect(row.sdat_pct_improvement).toBe(25) // (40-30)/40 * 100
})

it('clears pct_improvement when a score update makes it incomputable', async () => {
  const p = await h.createPatient({ last_name: 'A', first_name: 'B', sdat_begin_score: 40, sdat_end_score: 20 })
  await h.updatePatient({ id: p.id, sdat_begin_score: '' })
  const row = db.prepare('SELECT sdat_pct_improvement FROM patients WHERE id = ?').get(p.id)
  expect(row.sdat_pct_improvement).toBeNull()
})

// ── soft delete / restore ──────────────────────────────────────────────────

it('soft-deletes a patient: sets deleted status, deactivates, records history', async () => {
  const p = await h.createPatient({ last_name: 'Err', first_name: 'Or', userId: 1 })
  await h.deletePatient({ patientId: p.id, userId: 1 })
  const row = db.prepare('SELECT * FROM patients WHERE id = ?').get(p.id)
  expect(row.current_status).toBe('deleted')
  expect(row.is_active).toBe(0)
  const history = db.prepare("SELECT * FROM patient_status_history WHERE patient_id = ? AND status = 'deleted'").all(p.id)
  expect(history).toHaveLength(1)
})

it('restores a deleted patient to on_hold by default', async () => {
  const p = await h.createPatient({ last_name: 'Err', first_name: 'Or', userId: 1 })
  await h.deletePatient({ patientId: p.id, userId: 1 })
  await h.restorePatient({ patientId: p.id, userId: 1 })
  const row = db.prepare('SELECT * FROM patients WHERE id = ?').get(p.id)
  expect(row.current_status).toBe('on_hold')
  expect(row.is_active).toBe(1)
})

it('listPatients hides deleted by default, exposes them via status:deleted and includeDeleted', async () => {
  await h.createPatient({ last_name: 'Active', first_name: 'A', userId: 1 })
  const p2 = await h.createPatient({ last_name: 'Gone', first_name: 'B', userId: 1 })
  await h.deletePatient({ patientId: p2.id, userId: 1 })

  expect(await h.listPatients({})).toHaveLength(1)
  const deleted = await h.listPatients({ status: 'deleted' })
  expect(deleted).toHaveLength(1)
  expect(deleted[0].last_name).toBe('Gone')
  expect(await h.listPatients({ includeDeleted: true })).toHaveLength(2)
})
