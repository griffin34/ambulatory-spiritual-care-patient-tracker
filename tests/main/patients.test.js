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
