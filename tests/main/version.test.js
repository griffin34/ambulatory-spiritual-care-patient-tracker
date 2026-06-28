import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db'
import { createVersionHandlers } from '../../src/main/ipc/version'

let db, h
const app = { getVersion: () => '1.1.0' }

beforeEach(() => {
  db = openDb(':memory:')
  runMigrations(db)
  h = createVersionHandlers(db, app)
})
afterEach(() => db.close())

it('returns the app version', () => {
  expect(h.getVersion()).toBe('1.1.0')
})

it('flags What\'s New when no version has been seen yet', () => {
  const status = h.getReleaseStatus()
  expect(status.current).toBe('1.1.0')
  expect(status.lastSeen).toBeNull()
  expect(status.shouldShowWhatsNew).toBe(true)
})

it('stops flagging What\'s New after the version is marked seen', () => {
  h.markVersionSeen()
  const status = h.getReleaseStatus()
  expect(status.lastSeen).toBe('1.1.0')
  expect(status.shouldShowWhatsNew).toBe(false)
})

it('flags What\'s New again after a version bump', () => {
  h.markVersionSeen()
  const h2 = createVersionHandlers(db, { getVersion: () => '1.2.0' })
  expect(h2.getReleaseStatus().shouldShowWhatsNew).toBe(true)
})
