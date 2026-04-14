import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db'
import { createPatientHandlers } from '../../src/main/ipc/patients'
import { createAppointmentHandlers } from '../../src/main/ipc/appointments'

let db, ph, ah, patientId
beforeEach(async () => {
  db = openDb(':memory:')
  runMigrations(db)
  ph = createPatientHandlers(db)
  ah = createAppointmentHandlers(db)
  const p = await ph.createPatient({ last_name: 'Test', first_name: 'Patient', userId: null })
  patientId = p.id
})
afterEach(() => db.close())

it('creates an appointment', async () => {
  const a = await ah.createAppointment({ patient_id: patientId, date: '2026-04-14', time: '10:00', status: 'scheduled' })
  expect(a.id).toBeTruthy()
  expect(a.patient_id).toBe(patientId)
})

it('lists appointments for a day', async () => {
  await ah.createAppointment({ patient_id: patientId, date: '2026-04-14', time: '10:00', status: 'scheduled' })
  await ah.createAppointment({ patient_id: patientId, date: '2026-04-15', time: '09:00', status: 'scheduled' })
  const list = await ah.getAppointmentsForDay({ date: '2026-04-14' })
  expect(list).toHaveLength(1)
  expect(list[0].date).toBe('2026-04-14')
})

it('updates appointment status', async () => {
  const a = await ah.createAppointment({ patient_id: patientId, date: '2026-04-14', time: '10:00', status: 'scheduled' })
  const updated = await ah.updateAppointment({ id: a.id, status: 'completed' })
  expect(updated.status).toBe('completed')
})
