import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db'
import { createAdminHandlers } from '../../src/main/ipc/admin'

let db, h
beforeEach(() => {
  db = openDb(':memory:')
  runMigrations(db)
  h = createAdminHandlers(db)
})
afterEach(() => db.close())

it('creates a user with hashed password', async () => {
  const u = await h.createUser({ name: 'Jane', email: 'j@b.com', password: 'pass123', role: 'coordinator' })
  expect(u.id).toBeTruthy()
  expect(u.password_hash).toBeUndefined() // never returned
  expect(u.role).toBe('coordinator')
})

it('deactivates a user', async () => {
  const u = await h.createUser({ name: 'Jane', email: 'j@b.com', password: 'pass123', role: 'coordinator' })
  await h.setUserActive({ id: u.id, is_active: 0 })
  const updated = db.prepare('SELECT * FROM users WHERE id = ?').get(u.id)
  expect(updated.is_active).toBe(0)
})

it('creates and lists LoV entries', async () => {
  await h.upsertLov({ category: 'religion', value: 'Catholic', sort_order: 1 })
  const lovs = await h.listLovs({ category: 'religion' })
  expect(lovs).toHaveLength(1)
  expect(lovs[0].value).toBe('Catholic')
})

it('soft-deletes a LoV entry', async () => {
  const l = await h.upsertLov({ category: 'religion', value: 'Catholic', sort_order: 1 })
  await h.deleteLov({ id: l.id })
  const active = await h.listLovs({ category: 'religion' })
  expect(active).toHaveLength(0)
  const all = db.prepare("SELECT * FROM list_of_values WHERE id = ?").get(l.id)
  expect(all.is_active).toBe(0)
})
