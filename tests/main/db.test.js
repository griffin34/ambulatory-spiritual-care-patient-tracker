import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db'

let db
beforeEach(() => {
  db = openDb(':memory:')
  runMigrations(db)
})
afterEach(() => db.close())

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
