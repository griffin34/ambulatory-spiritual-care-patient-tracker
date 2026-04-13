import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db'
import { createAuthHandlers } from '../../src/main/ipc/auth'

let db, handlers
beforeEach(() => {
  db = openDb(':memory:')
  runMigrations(db)
  handlers = createAuthHandlers(db)
})
afterEach(() => db.close())

it('returns needsFirstRun true when no users exist', async () => {
  const result = await handlers.checkFirstRun()
  expect(result.needsFirstRun).toBe(true)
})

it('createFirstAdmin creates an admin user and returns session', async () => {
  const result = await handlers.createFirstAdmin({ name: 'Admin', email: 'a@b.com', password: 'secret123' })
  expect(result.user.role).toBe('admin')
  expect(result.token).toBeTruthy()
})

it('login succeeds with correct credentials', async () => {
  await handlers.createFirstAdmin({ name: 'Admin', email: 'a@b.com', password: 'secret123' })
  const result = await handlers.login({ email: 'a@b.com', password: 'secret123' })
  expect(result.user.email).toBe('a@b.com')
  expect(result.token).toBeTruthy()
})

it('login fails with wrong password', async () => {
  await handlers.createFirstAdmin({ name: 'Admin', email: 'a@b.com', password: 'secret123' })
  const result = await handlers.login({ email: 'a@b.com', password: 'wrong' })
  expect(result.error).toBeTruthy()
})
