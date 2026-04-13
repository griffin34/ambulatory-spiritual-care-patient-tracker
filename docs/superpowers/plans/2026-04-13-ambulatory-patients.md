# Ambulatory Patient Tracking System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a portable Electron desktop app for ambulatory scheduling coordinators to track patients, appointments, and generate reports — runs on locked-down Windows hospital PCs with no installation required.

**Architecture:** Electron main process owns the SQLite database via `better-sqlite3` and exposes all data operations to the React renderer through typed IPC handlers via a `preload.js` context bridge. The renderer is a React + Vite SPA with React Router for navigation.

**Tech Stack:** Electron 28, React 18, Vite 5, better-sqlite3, bcryptjs, SheetJS (xlsx), react-router-dom, date-fns, Vitest, electron-builder (portable Windows target)

---

## File Structure

```
src/
  main/
    index.js              # Electron app entry, BrowserWindow, lifecycle
    preload.js            # contextBridge — exposes ipc.invoke to renderer
    db.js                 # DB connection singleton + runMigrations()
    seed.js               # Default LoV seed data
    ipc/
      auth.js             # login, logout, getSession, createFirstAdmin
      patients.js         # listPatients, getPatient, createPatient, updatePatient, transitionStatus
      appointments.js     # listAppointments, getAppointmentsForDay, createAppointment, updateAppointment
      reports.js          # referralsBySource, firstAppointments, patientsDropped
      admin.js            # listUsers, createUser, updateUser, resetPassword, listLovs, upsertLov, deleteLov, listConsultants, upsertConsultant
      excel.js            # importFromExcel, exportToExcel
  renderer/
    main.jsx              # ReactDOM.createRoot entry
    App.jsx               # Router + ProtectedRoute + Layout
    components/
      Sidebar.jsx
      StatusBadge.jsx
      DateRangePicker.jsx
      BarChart.jsx
    pages/
      Login.jsx
      FirstRun.jsx
      WorkQueue.jsx
      PatientDetail.jsx
      Appointments.jsx
      Reports.jsx
      Admin.jsx
    hooks/
      useAuth.jsx         # AuthContext + useAuth()
      useIpc.js           # thin wrapper: ipc.invoke(channel, args)
    styles/
      globals.css
tests/
  main/
    db.test.js
    auth.test.js
    patients.test.js
    appointments.test.js
    reports.test.js
    admin.test.js
    excel.test.js
package.json
vite.config.js
electron-builder.config.js
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `package.json`
- Create: `vite.config.js`
- Create: `src/main/index.js`
- Create: `src/main/preload.js`
- Create: `src/renderer/main.jsx`
- Create: `src/renderer/App.jsx`
- Create: `electron-builder.config.js`

- [ ] **Step 1: Init project and install dependencies**

```bash
cd /Users/jgriffin/dev/ambulatory-patients
npm init -y
npm install electron better-sqlite3 bcryptjs xlsx date-fns
npm install --save-dev vite @vitejs/plugin-react react react-dom react-router-dom vitest electron-builder @testing-library/react @testing-library/jest-dom jsdom
```

- [ ] **Step 2: Write `package.json` scripts**

```json
{
  "name": "ambulatory-patients",
  "version": "1.0.0",
  "main": "src/main/index.js",
  "scripts": {
    "dev": "concurrently \"vite\" \"electron .\"",
    "build:renderer": "vite build",
    "build": "npm run build:renderer && electron-builder",
    "test": "vitest run tests/main"
  }
}
```

Also install: `npm install --save-dev concurrently`

- [ ] **Step 3: Write `vite.config.js`**

```js
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  root: 'src/renderer',
  build: { outDir: '../../dist/renderer' },
  server: { port: 5173 }
})
```

- [ ] **Step 4: Write `src/main/preload.js`**

```js
const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('ipc', {
  invoke: (channel, args) => ipcRenderer.invoke(channel, args)
})
```

- [ ] **Step 5: Write `src/main/index.js`**

```js
const { app, BrowserWindow, ipcMain } = require('electron')
const path = require('path')
const { runMigrations } = require('./db')
const registerAuth = require('./ipc/auth')
const registerPatients = require('./ipc/patients')
const registerAppointments = require('./ipc/appointments')
const registerReports = require('./ipc/reports')
const registerAdmin = require('./ipc/admin')
const registerExcel = require('./ipc/excel')

const isDev = process.env.NODE_ENV === 'development'

function createWindow() {
  const win = new BrowserWindow({
    width: 1280, height: 800,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  })
  if (isDev) {
    win.loadURL('http://localhost:5173')
  } else {
    win.loadFile(path.join(__dirname, '../../dist/renderer/index.html'))
  }
}

app.whenReady().then(() => {
  runMigrations()
  registerAuth(ipcMain)
  registerPatients(ipcMain)
  registerAppointments(ipcMain)
  registerReports(ipcMain)
  registerAdmin(ipcMain)
  registerExcel(ipcMain)
  createWindow()
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
```

- [ ] **Step 6: Write `src/renderer/main.jsx`**

```jsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './styles/globals.css'

ReactDOM.createRoot(document.getElementById('root')).render(<App />)
```

- [ ] **Step 7: Write `electron-builder.config.js`**

```js
module.exports = {
  appId: 'org.hospital.ambulatory-patients',
  productName: 'Ambulatory Patients',
  directories: { output: 'release' },
  files: ['dist/renderer/**/*', 'src/main/**/*', 'node_modules/**/*'],
  win: {
    target: [{ target: 'portable', arch: ['x64'] }],
    icon: 'assets/icon.ico'
  }
}
```

- [ ] **Step 8: Add `src/renderer/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Ambulatory Patients</title></head>
<body><div id="root"></div><script type="module" src="/main.jsx"></script></body>
</html>
```

- [ ] **Step 9: Verify app launches**

```bash
npm run dev
```
Expected: Electron window opens, React renders (blank page is fine)

- [ ] **Step 10: Commit**

```bash
git init
git add .
git commit -m "feat: scaffold Electron + React + Vite project"
```

---

## Task 2: Database Schema

**Files:**
- Create: `src/main/db.js`
- Create: `src/main/seed.js`
- Create: `tests/main/db.test.js`

- [ ] **Step 1: Write failing test**

```js
// tests/main/db.test.js
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
```

- [ ] **Step 2: Run test — verify it fails**

```bash
npm test -- db.test.js
```
Expected: FAIL — `openDb` not found

- [ ] **Step 3: Write `src/main/db.js`**

```js
const Database = require('better-sqlite3')
const path = require('path')
const { app } = require('electron')

let _db = null

function openDb(file) {
  const dbPath = file || path.join(app.getPath('userData'), 'ambulatory.db')
  return new Database(dbPath)
}

function getDb() {
  if (!_db) _db = openDb()
  return _db
}

function runMigrations(db) {
  const instance = db || getDb()
  instance.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK(role IN ('admin','coordinator')),
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS patients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mrn TEXT,
      last_name TEXT NOT NULL,
      first_name TEXT NOT NULL,
      middle_name TEXT,
      phone TEXT,
      date_of_referral TEXT,
      referral_source_id INTEGER REFERENCES list_of_values(id),
      religion_id INTEGER REFERENCES list_of_values(id),
      language_id INTEGER REFERENCES list_of_values(id),
      current_status TEXT NOT NULL DEFAULT 'ready_to_schedule',
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS patient_status_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      status TEXT NOT NULL,
      changed_by INTEGER REFERENCES users(id),
      changed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS appointments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      date TEXT NOT NULL,
      time TEXT NOT NULL,
      type_id INTEGER REFERENCES list_of_values(id),
      consultant_id INTEGER REFERENCES consultants(id),
      is_last_appointment INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'scheduled' CHECK(status IN ('scheduled','completed','no_show','cancelled')),
      notes TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS consultants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS list_of_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      value TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER REFERENCES users(id),
      action TEXT NOT NULL,
      entity TEXT NOT NULL,
      entity_id INTEGER,
      timestamp TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `)
}

module.exports = { openDb, getDb, runMigrations }
```

- [ ] **Step 4: Run test — verify it passes**

```bash
npm test -- db.test.js
```
Expected: PASS

- [ ] **Step 5: Write `src/main/seed.js`**

```js
function seedLovs(db) {
  const insert = db.prepare('INSERT OR IGNORE INTO list_of_values (category, value, sort_order) VALUES (?, ?, ?)')
  const lovs = [
    ['referral_source','Physician Referral',1],['referral_source','Hospital',2],
    ['referral_source','Self Referral',3],['referral_source','Family Member',4],
    ['referral_source','Social Worker',5],['referral_source','Other',6],
    ['religion','Catholic',1],['religion','Protestant',2],['religion','Jewish',3],
    ['religion','Muslim',4],['religion','Hindu',5],['religion','Buddhist',6],
    ['religion','Non-Religious',7],['religion','Other',8],
    ['language','English',1],['language','Spanish',2],['language','Mandarin',3],
    ['language','Polish',4],['language','Hindi',5],['language','Other',6],
    ['appointment_type','Telemed',1],['appointment_type','Video',2],
  ]
  const seedMany = db.transaction((rows) => rows.forEach(r => insert.run(...r)))
  seedMany(lovs)
}

module.exports = { seedLovs }
```

- [ ] **Step 6: Commit**

```bash
git add src/main/db.js src/main/seed.js tests/main/db.test.js
git commit -m "feat: database schema and migrations"
```

---

## Task 3: Auth IPC

**Files:**
- Create: `src/main/ipc/auth.js`
- Create: `tests/main/auth.test.js`

- [ ] **Step 1: Write failing tests**

```js
// tests/main/auth.test.js
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
```

- [ ] **Step 2: Run — verify fails**

```bash
npm test -- auth.test.js
```
Expected: FAIL

- [ ] **Step 3: Write `src/main/ipc/auth.js`**

```js
const bcrypt = require('bcryptjs')
const crypto = require('crypto')

// In-memory session store: token -> { userId, role }
const sessions = new Map()

function createAuthHandlers(db) {
  return {
    async checkFirstRun() {
      const count = db.prepare('SELECT COUNT(*) as n FROM users').get().n
      return { needsFirstRun: count === 0 }
    },

    async createFirstAdmin({ name, email, password }) {
      const hash = bcrypt.hashSync(password, 10)
      const { lastInsertRowid } = db.prepare(
        'INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, ?)'
      ).run(name, email, hash, 'admin')
      const user = db.prepare('SELECT id, name, email, role FROM users WHERE id = ?').get(lastInsertRowid)
      const token = crypto.randomUUID()
      sessions.set(token, { userId: user.id, role: user.role })
      return { user, token }
    },

    async login({ email, password }) {
      const user = db.prepare('SELECT * FROM users WHERE email = ? AND is_active = 1').get(email)
      if (!user || !bcrypt.compareSync(password, user.password_hash)) {
        return { error: 'Invalid email or password' }
      }
      const token = crypto.randomUUID()
      sessions.set(token, { userId: user.id, role: user.role })
      return { user: { id: user.id, name: user.name, email: user.email, role: user.role }, token }
    },

    async logout({ token }) {
      sessions.delete(token)
      return { ok: true }
    },

    async getSession({ token }) {
      const session = sessions.get(token)
      if (!session) return { user: null }
      const user = db.prepare('SELECT id, name, email, role FROM users WHERE id = ?').get(session.userId)
      return { user }
    },

    _sessions: sessions
  }
}

function register(ipcMain, db) {
  const h = createAuthHandlers(db)
  ipcMain.handle('auth:checkFirstRun', () => h.checkFirstRun())
  ipcMain.handle('auth:createFirstAdmin', (_, args) => h.createFirstAdmin(args))
  ipcMain.handle('auth:login', (_, args) => h.login(args))
  ipcMain.handle('auth:logout', (_, args) => h.logout(args))
  ipcMain.handle('auth:getSession', (_, args) => h.getSession(args))
}

module.exports = register
module.exports.createAuthHandlers = createAuthHandlers
```

- [ ] **Step 4: Run — verify passes**

```bash
npm test -- auth.test.js
```
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add src/main/ipc/auth.js tests/main/auth.test.js
git commit -m "feat: auth IPC — login, session, first-run"
```

---

## Task 4: Patient IPC

**Files:**
- Create: `src/main/ipc/patients.js`
- Create: `tests/main/patients.test.js`

- [ ] **Step 1: Write failing tests**

```js
// tests/main/patients.test.js
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
```

- [ ] **Step 2: Run — verify fails**

```bash
npm test -- patients.test.js
```

- [ ] **Step 3: Write `src/main/ipc/patients.js`**

```js
function createPatientHandlers(db) {
  return {
    async createPatient({ last_name, first_name, middle_name, mrn, phone, date_of_referral, referral_source_id, religion_id, language_id, userId }) {
      const { lastInsertRowid } = db.prepare(`
        INSERT INTO patients (last_name, first_name, middle_name, mrn, phone, date_of_referral, referral_source_id, religion_id, language_id, current_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'ready_to_schedule')
      `).run(last_name, first_name, middle_name||null, mrn||null, phone||null, date_of_referral||null, referral_source_id||null, religion_id||null, language_id||null)

      db.prepare('INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)').run(lastInsertRowid, 'ready_to_schedule', userId||null)

      return db.prepare('SELECT * FROM patients WHERE id = ?').get(lastInsertRowid)
    },

    async getPatient({ id }) {
      const patient = db.prepare('SELECT * FROM patients WHERE id = ?').get(id)
      if (!patient) return null
      patient.statusHistory = db.prepare(`
        SELECT h.*, u.name as changed_by_name FROM patient_status_history h
        LEFT JOIN users u ON u.id = h.changed_by
        WHERE h.patient_id = ? ORDER BY h.changed_at DESC
      `).all(id)
      patient.appointments = db.prepare(`
        SELECT a.*, c.name as consultant_name, l.value as type_label
        FROM appointments a
        LEFT JOIN consultants c ON c.id = a.consultant_id
        LEFT JOIN list_of_values l ON l.id = a.type_id
        WHERE a.patient_id = ? ORDER BY a.date DESC, a.time DESC
      `).all(id)
      return patient
    },

    async listPatients({ status, referral_source_id, search }) {
      let sql = `
        SELECT p.*, rs.value as referral_source,
          (SELECT a.date || ' ' || a.time FROM appointments a WHERE a.patient_id = p.id AND a.status = 'scheduled' AND a.date >= date('now') ORDER BY a.date, a.time LIMIT 1) as next_appointment
        FROM patients p
        LEFT JOIN list_of_values rs ON rs.id = p.referral_source_id
        WHERE p.is_active = 1
      `
      const params = []
      if (status) { sql += ' AND p.current_status = ?'; params.push(status) }
      if (referral_source_id) { sql += ' AND p.referral_source_id = ?'; params.push(referral_source_id) }
      if (search) { sql += ' AND (p.last_name LIKE ? OR p.first_name LIKE ? OR p.mrn LIKE ?)'; params.push(`%${search}%`, `%${search}%`, `%${search}%`) }
      sql += ' ORDER BY p.date_of_referral ASC'
      return db.prepare(sql).all(...params)
    },

    async updatePatient({ id, ...fields }) {
      const allowed = ['last_name','first_name','middle_name','mrn','phone','date_of_referral','referral_source_id','religion_id','language_id']
      const updates = Object.entries(fields).filter(([k]) => allowed.includes(k))
      if (!updates.length) return db.prepare('SELECT * FROM patients WHERE id = ?').get(id)
      const sql = `UPDATE patients SET ${updates.map(([k]) => `${k} = ?`).join(', ')} WHERE id = ?`
      db.prepare(sql).run(...updates.map(([,v]) => v), id)
      return db.prepare('SELECT * FROM patients WHERE id = ?').get(id)
    },

    async transitionStatus({ patientId, status, userId }) {
      db.prepare('UPDATE patients SET current_status = ? WHERE id = ?').run(status, patientId)
      db.prepare('INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)').run(patientId, status, userId||null)
      return db.prepare('SELECT * FROM patients WHERE id = ?').get(patientId)
    }
  }
}

function register(ipcMain, db) {
  const h = createPatientHandlers(db)
  ipcMain.handle('patients:list', (_, args) => h.listPatients(args || {}))
  ipcMain.handle('patients:get', (_, args) => h.getPatient(args))
  ipcMain.handle('patients:create', (_, args) => h.createPatient(args))
  ipcMain.handle('patients:update', (_, args) => h.updatePatient(args))
  ipcMain.handle('patients:transitionStatus', (_, args) => h.transitionStatus(args))
}

module.exports = register
module.exports.createPatientHandlers = createPatientHandlers
```

- [ ] **Step 4: Run — verify passes**

```bash
npm test -- patients.test.js
```
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add src/main/ipc/patients.js tests/main/patients.test.js
git commit -m "feat: patient IPC — CRUD and status transitions"
```

---

## Task 5: Appointment IPC

**Files:**
- Create: `src/main/ipc/appointments.js`
- Create: `tests/main/appointments.test.js`

- [ ] **Step 1: Write failing tests**

```js
// tests/main/appointments.test.js
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
  const p = await ph.createPatient({ last_name: 'Test', first_name: 'Patient', userId: 1 })
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
```

- [ ] **Step 2: Run — verify fails**

```bash
npm test -- appointments.test.js
```

- [ ] **Step 3: Write `src/main/ipc/appointments.js`**

```js
function createAppointmentHandlers(db) {
  return {
    async createAppointment({ patient_id, date, time, type_id, consultant_id, is_last_appointment, status, notes }) {
      const { lastInsertRowid } = db.prepare(`
        INSERT INTO appointments (patient_id, date, time, type_id, consultant_id, is_last_appointment, status, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(patient_id, date, time, type_id||null, consultant_id||null, is_last_appointment||0, status||'scheduled', notes||null)
      return db.prepare('SELECT * FROM appointments WHERE id = ?').get(lastInsertRowid)
    },

    async updateAppointment({ id, ...fields }) {
      const allowed = ['date','time','type_id','consultant_id','is_last_appointment','status','notes']
      const updates = Object.entries(fields).filter(([k]) => allowed.includes(k))
      if (!updates.length) return db.prepare('SELECT * FROM appointments WHERE id = ?').get(id)
      db.prepare(`UPDATE appointments SET ${updates.map(([k]) => `${k} = ?`).join(', ')} WHERE id = ?`).run(...updates.map(([,v]) => v), id)
      return db.prepare('SELECT * FROM appointments WHERE id = ?').get(id)
    },

    async getAppointmentsForDay({ date }) {
      return db.prepare(`
        SELECT a.*, p.last_name, p.first_name, p.mrn,
          c.name as consultant_name, l.value as type_label
        FROM appointments a
        JOIN patients p ON p.id = a.patient_id
        LEFT JOIN consultants c ON c.id = a.consultant_id
        LEFT JOIN list_of_values l ON l.id = a.type_id
        WHERE a.date = ?
        ORDER BY a.time ASC
      `).all(date)
    },

    async getDaysWithAppointments({ from, to }) {
      return db.prepare(`
        SELECT DISTINCT date FROM appointments WHERE date BETWEEN ? AND ? ORDER BY date
      `).all(from, to).map(r => r.date)
    }
  }
}

function register(ipcMain, db) {
  const h = createAppointmentHandlers(db)
  ipcMain.handle('appointments:create', (_, args) => h.createAppointment(args))
  ipcMain.handle('appointments:update', (_, args) => h.updateAppointment(args))
  ipcMain.handle('appointments:forDay', (_, args) => h.getAppointmentsForDay(args))
  ipcMain.handle('appointments:daysWithAppointments', (_, args) => h.getDaysWithAppointments(args))
}

module.exports = register
module.exports.createAppointmentHandlers = createAppointmentHandlers
```

- [ ] **Step 4: Run — verify passes**

```bash
npm test -- appointments.test.js
```

- [ ] **Step 5: Commit**

```bash
git add src/main/ipc/appointments.js tests/main/appointments.test.js
git commit -m "feat: appointment IPC — CRUD and day view queries"
```

---

## Task 6: Admin IPC (Users + LoVs)

**Files:**
- Create: `src/main/ipc/admin.js`
- Create: `tests/main/admin.test.js`

- [ ] **Step 1: Write failing tests**

```js
// tests/main/admin.test.js
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
```

- [ ] **Step 2: Run — verify fails**

```bash
npm test -- admin.test.js
```

- [ ] **Step 3: Write `src/main/ipc/admin.js`**

```js
const bcrypt = require('bcryptjs')

function createAdminHandlers(db) {
  return {
    async listUsers() {
      return db.prepare('SELECT id, name, email, role, is_active, created_at FROM users ORDER BY name').all()
    },

    async createUser({ name, email, password, role }) {
      const hash = bcrypt.hashSync(password, 10)
      const { lastInsertRowid } = db.prepare(
        'INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, ?)'
      ).run(name, email, hash, role)
      return db.prepare('SELECT id, name, email, role, is_active FROM users WHERE id = ?').get(lastInsertRowid)
    },

    async setUserActive({ id, is_active }) {
      db.prepare('UPDATE users SET is_active = ? WHERE id = ?').run(is_active, id)
      return db.prepare('SELECT id, name, email, role, is_active FROM users WHERE id = ?').get(id)
    },

    async resetPassword({ id, newPassword }) {
      const hash = bcrypt.hashSync(newPassword, 10)
      db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(hash, id)
      return { ok: true }
    },

    async listLovs({ category }) {
      return db.prepare('SELECT * FROM list_of_values WHERE category = ? AND is_active = 1 ORDER BY sort_order, value').all(category)
    },

    async upsertLov({ id, category, value, sort_order }) {
      if (id) {
        db.prepare('UPDATE list_of_values SET value = ?, sort_order = ? WHERE id = ?').run(value, sort_order||0, id)
        return db.prepare('SELECT * FROM list_of_values WHERE id = ?').get(id)
      }
      const { lastInsertRowid } = db.prepare('INSERT INTO list_of_values (category, value, sort_order) VALUES (?, ?, ?)').run(category, value, sort_order||0)
      return db.prepare('SELECT * FROM list_of_values WHERE id = ?').get(lastInsertRowid)
    },

    async deleteLov({ id }) {
      db.prepare('UPDATE list_of_values SET is_active = 0 WHERE id = ?').run(id)
      return { ok: true }
    },

    async restoreLov({ id }) {
      db.prepare('UPDATE list_of_values SET is_active = 1 WHERE id = ?').run(id)
      return { ok: true }
    },

    async listConsultants() {
      return db.prepare('SELECT * FROM consultants ORDER BY name').all()
    },

    async upsertConsultant({ id, name }) {
      if (id) {
        db.prepare('UPDATE consultants SET name = ? WHERE id = ?').run(name, id)
        return db.prepare('SELECT * FROM consultants WHERE id = ?').get(id)
      }
      const { lastInsertRowid } = db.prepare('INSERT INTO consultants (name) VALUES (?)').run(name)
      return db.prepare('SELECT * FROM consultants WHERE id = ?').get(lastInsertRowid)
    },

    async setConsultantActive({ id, is_active }) {
      db.prepare('UPDATE consultants SET is_active = ? WHERE id = ?').run(is_active, id)
      return db.prepare('SELECT * FROM consultants WHERE id = ?').get(id)
    }
  }
}

function register(ipcMain, db) {
  const h = createAdminHandlers(db)
  ipcMain.handle('admin:listUsers', () => h.listUsers())
  ipcMain.handle('admin:createUser', (_, args) => h.createUser(args))
  ipcMain.handle('admin:setUserActive', (_, args) => h.setUserActive(args))
  ipcMain.handle('admin:resetPassword', (_, args) => h.resetPassword(args))
  ipcMain.handle('admin:listLovs', (_, args) => h.listLovs(args))
  ipcMain.handle('admin:upsertLov', (_, args) => h.upsertLov(args))
  ipcMain.handle('admin:deleteLov', (_, args) => h.deleteLov(args))
  ipcMain.handle('admin:restoreLov', (_, args) => h.restoreLov(args))
  ipcMain.handle('admin:listConsultants', () => h.listConsultants())
  ipcMain.handle('admin:upsertConsultant', (_, args) => h.upsertConsultant(args))
  ipcMain.handle('admin:setConsultantActive', (_, args) => h.setConsultantActive(args))
}

module.exports = register
module.exports.createAdminHandlers = createAdminHandlers
```

- [ ] **Step 4: Run — verify passes**

```bash
npm test -- admin.test.js
```

- [ ] **Step 5: Commit**

```bash
git add src/main/ipc/admin.js tests/main/admin.test.js
git commit -m "feat: admin IPC — user management and LoV CRUD"
```

---

## Task 7: Reports IPC

**Files:**
- Create: `src/main/ipc/reports.js`
- Create: `tests/main/reports.test.js`

- [ ] **Step 1: Write failing tests**

```js
// tests/main/reports.test.js
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db'
import { createPatientHandlers } from '../../src/main/ipc/patients'
import { createAppointmentHandlers } from '../../src/main/ipc/appointments'
import { createReportHandlers } from '../../src/main/ipc/reports'

let db, ph, ah, rh

beforeEach(async () => {
  db = openDb(':memory:')
  runMigrations(db)
  ph = createPatientHandlers(db)
  ah = createAppointmentHandlers(db)
  rh = createReportHandlers(db)

  // Seed: 2 patients referred in range, 1 outside
  db.prepare("INSERT INTO list_of_values (id,category,value,sort_order) VALUES (1,'referral_source','Physician',1)").run()
  db.prepare("INSERT INTO list_of_values (id,category,value,sort_order) VALUES (2,'referral_source','Hospital',2)").run()

  await ph.createPatient({ last_name: 'A', first_name: 'A', date_of_referral: '2026-03-05', referral_source_id: 1, userId: 1 })
  await ph.createPatient({ last_name: 'B', first_name: 'B', date_of_referral: '2026-03-10', referral_source_id: 1, userId: 1 })
  await ph.createPatient({ last_name: 'C', first_name: 'C', date_of_referral: '2026-02-01', referral_source_id: 2, userId: 1 })
})
afterEach(() => db.close())

it('referralsBySource returns counts grouped by source in range', async () => {
  const results = await rh.referralsBySource({ from: '2026-03-01', to: '2026-03-31' })
  expect(results).toHaveLength(1)
  expect(results[0].source).toBe('Physician')
  expect(results[0].count).toBe(2)
})

it('patientsDropped returns patients who entered dropped status in range', async () => {
  const p = await ph.createPatient({ last_name: 'D', first_name: 'D', date_of_referral: '2026-03-01', userId: 1 })
  db.prepare("INSERT INTO patient_status_history (patient_id, status, changed_by, changed_at) VALUES (?, 'dropped', 1, '2026-03-15')").run(p.id)
  const results = await rh.patientsDropped({ from: '2026-03-01', to: '2026-03-31' })
  expect(results).toHaveLength(1)
  expect(results[0].patient_id).toBe(p.id)
})
```

- [ ] **Step 2: Run — verify fails**

```bash
npm test -- reports.test.js
```

- [ ] **Step 3: Write `src/main/ipc/reports.js`**

```js
function createReportHandlers(db) {
  return {
    async referralsBySource({ from, to }) {
      return db.prepare(`
        SELECT l.value as source, COUNT(*) as count
        FROM patients p
        LEFT JOIN list_of_values l ON l.id = p.referral_source_id
        WHERE p.date_of_referral BETWEEN ? AND ? AND p.is_active = 1
        GROUP BY p.referral_source_id
        ORDER BY count DESC
      `).all(from, to)
    },

    async firstAppointments({ from, to }) {
      return db.prepare(`
        SELECT p.id as patient_id, p.last_name, p.first_name, p.mrn,
          MIN(a.date) as first_appt_date, c.name as consultant_name
        FROM appointments a
        JOIN patients p ON p.id = a.patient_id
        LEFT JOIN consultants c ON c.id = a.consultant_id
        WHERE a.status IN ('completed','scheduled')
        GROUP BY a.patient_id
        HAVING MIN(a.date) BETWEEN ? AND ?
        ORDER BY first_appt_date ASC
      `).all(from, to)
    },

    async patientsDropped({ from, to }) {
      return db.prepare(`
        SELECT h.patient_id, h.changed_at, h.changed_by,
          p.last_name, p.first_name, p.mrn,
          u.name as changed_by_name
        FROM patient_status_history h
        JOIN patients p ON p.id = h.patient_id
        LEFT JOIN users u ON u.id = h.changed_by
        WHERE h.status = 'dropped' AND h.changed_at BETWEEN ? AND ?
        ORDER BY h.changed_at ASC
      `).all(from, to)
    }
  }
}

function register(ipcMain, db) {
  const h = createReportHandlers(db)
  ipcMain.handle('reports:referralsBySource', (_, args) => h.referralsBySource(args))
  ipcMain.handle('reports:firstAppointments', (_, args) => h.firstAppointments(args))
  ipcMain.handle('reports:patientsDropped', (_, args) => h.patientsDropped(args))
}

module.exports = register
module.exports.createReportHandlers = createReportHandlers
```

- [ ] **Step 4: Run — verify passes**

```bash
npm test -- reports.test.js
```

- [ ] **Step 5: Commit**

```bash
git add src/main/ipc/reports.js tests/main/reports.test.js
git commit -m "feat: reports IPC — referrals, first appointments, drops"
```

---

## Task 8: Excel Import/Export IPC

**Files:**
- Create: `src/main/ipc/excel.js`
- Create: `tests/main/excel.test.js`

- [ ] **Step 1: Write failing tests**

```js
// tests/main/excel.test.js
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, runMigrations } from '../../src/main/db'
import { createPatientHandlers } from '../../src/main/ipc/patients'
import { createExcelHandlers } from '../../src/main/ipc/excel'
import XLSX from 'xlsx'
import path from 'path'
import fs from 'fs'
import os from 'os'

let db, ph, eh
beforeEach(async () => {
  db = openDb(':memory:')
  runMigrations(db)
  ph = createPatientHandlers(db)
  eh = createExcelHandlers(db)
  await ph.createPatient({ last_name: 'Smith', first_name: 'John', mrn: 'MRN-001', userId: 1 })
  await ph.createPatient({ last_name: 'Jones', first_name: 'Jane', mrn: 'MRN-002', userId: 1 })
})
afterEach(() => db.close())

it('exports patients to a valid xlsx file', async () => {
  const outPath = path.join(os.tmpdir(), `test-export-${Date.now()}.xlsx`)
  await eh.exportPatients({ filePath: outPath })
  expect(fs.existsSync(outPath)).toBe(true)
  const wb = XLSX.readFile(outPath)
  const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]])
  expect(rows).toHaveLength(2)
  fs.unlinkSync(outPath)
})

it('parses an xlsx file and returns rows for preview', async () => {
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet([
    { last_name: 'Brown', first_name: 'Bob', mrn: 'MRN-003', date_of_referral: '03/01/2026' }
  ]), 'Patients')
  const inPath = path.join(os.tmpdir(), `test-import-${Date.now()}.xlsx`)
  XLSX.writeFile(wb, inPath)
  const result = await eh.parseImportFile({ filePath: inPath })
  expect(result.rows).toHaveLength(1)
  expect(result.columns).toContain('last_name')
  fs.unlinkSync(inPath)
})
```

- [ ] **Step 2: Run — verify fails**

```bash
npm test -- excel.test.js
```

- [ ] **Step 3: Write `src/main/ipc/excel.js`**

```js
const XLSX = require('xlsx')

function createExcelHandlers(db) {
  return {
    async exportPatients({ filePath }) {
      const patients = db.prepare(`
        SELECT p.last_name, p.first_name, p.middle_name, p.mrn, p.phone,
          p.date_of_referral, rs.value as referral_source,
          rel.value as religion, lang.value as language,
          p.current_status, p.created_at
        FROM patients p
        LEFT JOIN list_of_values rs ON rs.id = p.referral_source_id
        LEFT JOIN list_of_values rel ON rel.id = p.religion_id
        LEFT JOIN list_of_values lang ON lang.id = p.language_id
        WHERE p.is_active = 1 ORDER BY p.last_name
      `).all()
      const wb = XLSX.utils.book_new()
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(patients), 'Patients')
      XLSX.writeFile(wb, filePath)
      return { ok: true, count: patients.length }
    },

    async exportReport({ filePath, rows, sheetName }) {
      const wb = XLSX.utils.book_new()
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(rows), sheetName || 'Report')
      XLSX.writeFile(wb, filePath)
      return { ok: true }
    },

    async parseImportFile({ filePath }) {
      const wb = XLSX.readFile(filePath)
      const sheet = wb.Sheets[wb.SheetNames[0]]
      const rows = XLSX.utils.sheet_to_json(sheet, { defval: '' })
      const columns = rows.length > 0 ? Object.keys(rows[0]) : []
      return { rows, columns }
    },

    async importPatients({ rows, columnMap, userId }) {
      // columnMap: { last_name: 'Last Name', first_name: 'First Name', ... }
      const insert = db.prepare(`
        INSERT INTO patients (last_name, first_name, middle_name, mrn, phone, date_of_referral, current_status)
        VALUES (?, ?, ?, ?, ?, ?, 'ready_to_schedule')
      `)
      const addHistory = db.prepare(
        'INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)'
      )
      let imported = 0
      const importAll = db.transaction((rows) => {
        for (const row of rows) {
          const get = (field) => (columnMap[field] ? (row[columnMap[field]] || null) : null)
          const { lastInsertRowid } = insert.run(
            get('last_name'), get('first_name'), get('middle_name'),
            get('mrn'), get('phone'), get('date_of_referral')
          )
          addHistory.run(lastInsertRowid, 'ready_to_schedule', userId || null)
          imported++
        }
      })
      importAll(rows)
      return { imported }
    }
  }
}

function register(ipcMain, db) {
  const h = createExcelHandlers(db)
  ipcMain.handle('excel:exportPatients', (_, args) => h.exportPatients(args))
  ipcMain.handle('excel:exportReport', (_, args) => h.exportReport(args))
  ipcMain.handle('excel:parseImportFile', (_, args) => h.parseImportFile(args))
  ipcMain.handle('excel:importPatients', (_, args) => h.importPatients(args))
}

module.exports = register
module.exports.createExcelHandlers = createExcelHandlers
```

- [ ] **Step 4: Run — verify passes**

```bash
npm test -- excel.test.js
```

- [ ] **Step 5: Run all tests together — verify nothing broken**

```bash
npm test
```
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add src/main/ipc/excel.js tests/main/excel.test.js
git commit -m "feat: Excel import and export IPC"
```

---

## Task 9: App Shell — Layout, Auth Context, Login, First Run

**Files:**
- Create: `src/renderer/styles/globals.css`
- Create: `src/renderer/hooks/useAuth.jsx`
- Create: `src/renderer/hooks/useIpc.js`
- Create: `src/renderer/components/Sidebar.jsx`
- Create: `src/renderer/pages/Login.jsx`
- Create: `src/renderer/pages/FirstRun.jsx`
- Create: `src/renderer/App.jsx`

- [ ] **Step 1: Write `src/renderer/hooks/useIpc.js`**

```js
export function useIpc() {
  return {
    invoke: (channel, args) => window.ipc.invoke(channel, args)
  }
}
```

- [ ] **Step 2: Write `src/renderer/hooks/useAuth.jsx`**

```jsx
import React, { createContext, useContext, useState, useEffect } from 'react'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [token, setToken] = useState(() => sessionStorage.getItem('token'))
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (token) {
      window.ipc.invoke('auth:getSession', { token }).then(({ user }) => {
        setUser(user)
        setLoading(false)
      })
    } else {
      setLoading(false)
    }
  }, [token])

  const login = async (email, password) => {
    const result = await window.ipc.invoke('auth:login', { email, password })
    if (result.error) return result
    setToken(result.token)
    setUser(result.user)
    sessionStorage.setItem('token', result.token)
    return result
  }

  const logout = async () => {
    await window.ipc.invoke('auth:logout', { token })
    sessionStorage.removeItem('token')
    setToken(null)
    setUser(null)
  }

  const completeFirstRun = (result) => {
    setToken(result.token)
    setUser(result.user)
    sessionStorage.setItem('token', result.token)
  }

  return (
    <AuthContext.Provider value={{ user, token, loading, login, logout, completeFirstRun }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  return useContext(AuthContext)
}
```

- [ ] **Step 3: Write `src/renderer/styles/globals.css`**

Copy the CSS from the approved mockups — use the same color palette, typography, and spacing. Key variables:

```css
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f0f2f5; color: #1a1a2e; }

:root {
  --sidebar-bg: #1a1a2e;
  --accent: #6366f1;
  --accent-hover: #4f46e5;
  --status-ready: #22c55e;
  --status-scheduled: #eab308;
  --status-completed: #3b82f6;
  --status-dropped: #ef4444;
  --status-onhold: #9ca3af;
  --border: #e2e8f0;
  --surface: #fff;
  --muted: #718096;
}
```

- [ ] **Step 4: Write `src/renderer/components/Sidebar.jsx`**

```jsx
import React from 'react'
import { NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'

export default function Sidebar() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  const handleLogout = async () => {
    await logout()
    navigate('/login')
  }

  const initials = user ? user.name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase() : '?'

  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <div className="app-name">Ambulatory</div>
        <div className="app-subtitle">Patient Tracking</div>
      </div>
      <nav className="sidebar-nav">
        <div className="nav-section">Main</div>
        <NavLink className={({isActive}) => `nav-item${isActive?' active':''}`} to="/queue">
          <span className="icon">☰</span> Work Queue
        </NavLink>
        <NavLink className={({isActive}) => `nav-item${isActive?' active':''}`} to="/appointments">
          <span className="icon">📅</span> Appointments
        </NavLink>
        <NavLink className={({isActive}) => `nav-item${isActive?' active':''}`} to="/reports">
          <span className="icon">📊</span> Reports
        </NavLink>
        {user?.role === 'admin' && <>
          <div className="nav-section">Admin</div>
          <NavLink className={({isActive}) => `nav-item${isActive?' active':''}`} to="/admin">
            <span className="icon">👥</span> Users &amp; Settings
          </NavLink>
        </>}
      </nav>
      <div className="sidebar-footer">
        <div className="user-info">
          <div className="avatar">{initials}</div>
          <div className="user-name">{user?.name}</div>
        </div>
        <button className="logout-btn" onClick={handleLogout}>Sign out</button>
      </div>
    </aside>
  )
}
```

- [ ] **Step 5: Write `src/renderer/pages/Login.jsx`**

```jsx
import React, { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'

export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const { login } = useAuth()
  const navigate = useNavigate()

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    const result = await login(email, password)
    setLoading(false)
    if (result.error) { setError(result.error); return }
    navigate('/queue')
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-logo">
          <div className="login-app-name">Ambulatory</div>
          <div className="login-app-subtitle">Patient Tracking</div>
        </div>
        <form onSubmit={handleSubmit}>
          {error && <div className="login-error">{error}</div>}
          <div className="field">
            <label>Email</label>
            <input type="email" value={email} onChange={e => setEmail(e.target.value)} required autoFocus />
          </div>
          <div className="field">
            <label>Password</label>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} required />
          </div>
          <button type="submit" className="btn btn-primary btn-full" disabled={loading}>
            {loading ? 'Signing in…' : 'Sign In'}
          </button>
        </form>
      </div>
    </div>
  )
}
```

- [ ] **Step 6: Write `src/renderer/pages/FirstRun.jsx`**

```jsx
import React, { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'

export default function FirstRun() {
  const [form, setForm] = useState({ name: '', email: '', password: '', confirm: '' })
  const [error, setError] = useState('')
  const { completeFirstRun } = useAuth()
  const navigate = useNavigate()

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (form.password !== form.confirm) { setError('Passwords do not match'); return }
    const result = await window.ipc.invoke('auth:createFirstAdmin', { name: form.name, email: form.email, password: form.password })
    completeFirstRun(result)
    navigate('/queue')
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-logo">
          <div className="login-app-name">Welcome</div>
          <div className="login-app-subtitle">Create your admin account to get started</div>
        </div>
        <form onSubmit={handleSubmit}>
          {error && <div className="login-error">{error}</div>}
          {['name','email','password','confirm'].map(field => (
            <div className="field" key={field}>
              <label>{field === 'confirm' ? 'Confirm Password' : field.charAt(0).toUpperCase() + field.slice(1)}</label>
              <input type={field.includes('pass') || field === 'confirm' ? 'password' : field === 'email' ? 'email' : 'text'} value={form[field]} onChange={e => setForm(f => ({...f, [field]: e.target.value}))} required />
            </div>
          ))}
          <button type="submit" className="btn btn-primary btn-full">Create Account</button>
        </form>
      </div>
    </div>
  )
}
```

- [ ] **Step 7: Write `src/renderer/App.jsx`**

```jsx
import React, { useEffect, useState } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth } from './hooks/useAuth'
import Sidebar from './components/Sidebar'
import Login from './pages/Login'
import FirstRun from './pages/FirstRun'
import WorkQueue from './pages/WorkQueue'
import PatientDetail from './pages/PatientDetail'
import Appointments from './pages/Appointments'
import Reports from './pages/Reports'
import Admin from './pages/Admin'

function AppRoutes() {
  const { user, loading } = useAuth()
  const [needsFirstRun, setNeedsFirstRun] = useState(null)

  useEffect(() => {
    window.ipc.invoke('auth:checkFirstRun').then(({ needsFirstRun }) => setNeedsFirstRun(needsFirstRun))
  }, [])

  if (loading || needsFirstRun === null) return <div className="loading-screen">Loading…</div>
  if (needsFirstRun) return <Routes><Route path="*" element={<FirstRun />} /></Routes>
  if (!user) return <Routes><Route path="*" element={<Login />} /></Routes>

  return (
    <div className="app-shell">
      <Sidebar />
      <main className="main">
        <Routes>
          <Route path="/" element={<Navigate to="/queue" replace />} />
          <Route path="/queue" element={<WorkQueue />} />
          <Route path="/queue/:id" element={<PatientDetail />} />
          <Route path="/appointments" element={<Appointments />} />
          <Route path="/reports" element={<Reports />} />
          {user.role === 'admin' && <Route path="/admin" element={<Admin />} />}
        </Routes>
      </main>
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <AppRoutes />
      </AuthProvider>
    </BrowserRouter>
  )
}
```

- [ ] **Step 8: Verify login flow works end-to-end**

```bash
npm run dev
```
Expected: First launch shows FirstRun page → create admin → redirects to Work Queue (blank)

- [ ] **Step 9: Commit**

```bash
git add src/renderer/
git commit -m "feat: app shell — login, first-run, layout, sidebar, auth context"
```

---

## Task 10: Work Queue Screen

**Files:**
- Create: `src/renderer/pages/WorkQueue.jsx`
- Create: `src/renderer/components/StatusBadge.jsx`

- [ ] **Step 1: Write `src/renderer/components/StatusBadge.jsx`**

```jsx
const STATUS_CONFIG = {
  ready_to_schedule: { label: 'Ready to Schedule', color: '#15803d', bg: '#f0fdf4', dot: '#22c55e' },
  scheduled:         { label: 'Scheduled',          color: '#a16207', bg: '#fefce8', dot: '#eab308' },
  completed:         { label: 'Completed',           color: '#1d4ed8', bg: '#eff6ff', dot: '#3b82f6' },
  dropped:           { label: 'Dropped',             color: '#dc2626', bg: '#fef2f2', dot: '#ef4444' },
  on_hold:           { label: 'On Hold',             color: '#6b7280', bg: '#f9fafb', dot: '#9ca3af' },
}

export default function StatusBadge({ status, size = 'md' }) {
  const cfg = STATUS_CONFIG[status] || STATUS_CONFIG.on_hold
  return (
    <span style={{ display:'inline-flex', alignItems:'center', gap:6, padding: size==='sm' ? '2px 8px':'4px 12px', borderRadius:20, fontSize: size==='sm'?10:11, fontWeight:700, textTransform:'uppercase', letterSpacing:'0.04em', background:cfg.bg, color:cfg.color }}>
      <span style={{ width:6, height:6, borderRadius:'50%', background:cfg.dot, flexShrink:0 }}></span>
      {cfg.label}
    </span>
  )
}

export { STATUS_CONFIG }
```

- [ ] **Step 2: Write `src/renderer/pages/WorkQueue.jsx`**

```jsx
import React, { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import StatusBadge, { STATUS_CONFIG } from '../components/StatusBadge'
import { useAuth } from '../hooks/useAuth'
import { format } from 'date-fns'

const STATUSES = ['ready_to_schedule','scheduled','completed','dropped','on_hold']

export default function WorkQueue() {
  const [patients, setPatients] = useState([])
  const [filters, setFilters] = useState({ status: '', search: '' })
  const [loading, setLoading] = useState(true)
  const navigate = useNavigate()
  const { token } = useAuth()

  const load = useCallback(async () => {
    setLoading(true)
    const list = await window.ipc.invoke('patients:list', filters)
    setPatients(list)
    setLoading(false)
  }, [filters])

  useEffect(() => { load() }, [load])

  const counts = STATUSES.reduce((acc, s) => ({ ...acc, [s]: patients.filter(p => p.current_status === s).length }), {})

  return (
    <div className="page">
      <div className="topbar">
        <h1>Work Queue</h1>
        <div className="topbar-right">
          <input className="search-input" placeholder="Search by name or MRN…" value={filters.search} onChange={e => setFilters(f => ({...f, search: e.target.value}))} />
          <button className="btn btn-primary" onClick={() => navigate('/queue/new')}>+ Add Patient</button>
        </div>
      </div>

      <div className="stats-bar">
        <div className="stat"><span className="stat-value">{patients.length}</span><span className="stat-label">Total Active</span></div>
        {STATUSES.map(s => (
          <div key={s} className="stat">
            <span className="stat-value" style={{ color: STATUS_CONFIG[s].dot }}>{counts[s]}</span>
            <span className="stat-label">{STATUS_CONFIG[s].label}</span>
          </div>
        ))}
      </div>

      <div className="filters">
        <span className="filter-label">Status</span>
        <button className={`filter-chip${!filters.status?' active':''}`} onClick={() => setFilters(f => ({...f, status:''}))}>All</button>
        {STATUSES.map(s => (
          <button key={s} className={`filter-chip${filters.status===s?' active':''}`} onClick={() => setFilters(f => ({...f, status: f.status===s?'':s}))} style={filters.status===s?{}:{borderColor: STATUS_CONFIG[s].dot+'66', color: STATUS_CONFIG[s].color}}>
            {STATUS_CONFIG[s].label}
          </button>
        ))}
      </div>

      <div className="table-area">
        <table>
          <thead><tr>
            <th>Patient Name</th><th>MRN</th><th>Referral Date</th>
            <th>Referral Source</th><th>Language</th><th>Next Appointment</th><th>Status</th><th></th>
          </tr></thead>
          <tbody>
            {loading ? <tr><td colSpan={8} style={{textAlign:'center',padding:32,color:'#a0aec0'}}>Loading…</td></tr>
            : patients.length === 0 ? <tr><td colSpan={8} style={{textAlign:'center',padding:32,color:'#a0aec0'}}>No patients found</td></tr>
            : patients.map(p => (
              <tr key={p.id} onClick={() => navigate(`/queue/${p.id}`)} style={{cursor:'pointer'}}>
                <td className="name">{p.last_name}, {p.first_name}{p.middle_name ? ` ${p.middle_name[0]}.`:''}</td>
                <td className="mrn">{p.mrn || '—'}</td>
                <td className="date">{p.date_of_referral ? format(new Date(p.date_of_referral), 'MM/dd/yyyy') : '—'}</td>
                <td>{p.referral_source || '—'}</td>
                <td>{p.language || '—'}</td>
                <td>{p.next_appointment ? format(new Date(p.next_appointment), 'MMM d, h:mm a') : <span style={{color:'#a0aec0',fontStyle:'italic'}}>None</span>}</td>
                <td><StatusBadge status={p.current_status} /></td>
                <td><button className="action-btn" onClick={e => {e.stopPropagation(); navigate(`/queue/${p.id}`)}}>View</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Verify in app**

```bash
npm run dev
```
Expected: Work Queue loads, shows patient table, filter chips change the list, clicking a row navigates to /queue/:id (404 for now)

- [ ] **Step 4: Commit**

```bash
git add src/renderer/pages/WorkQueue.jsx src/renderer/components/StatusBadge.jsx
git commit -m "feat: Work Queue screen with filters and stats bar"
```

---

## Task 11: Patient Detail Screen

**Files:**
- Create: `src/renderer/pages/PatientDetail.jsx`

- [ ] **Step 1: Write `src/renderer/pages/PatientDetail.jsx`**

```jsx
import React, { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import StatusBadge, { STATUS_CONFIG } from '../components/StatusBadge'
import { useAuth } from '../hooks/useAuth'
import { format } from 'date-fns'

const STATUSES = ['ready_to_schedule','scheduled','completed','dropped','on_hold']

export default function PatientDetail() {
  const { id } = useParams()
  const isNew = id === 'new'
  const [patient, setPatient] = useState(null)
  const [editingProfile, setEditingProfile] = useState(isNew)
  const [showStatusMenu, setShowStatusMenu] = useState(false)
  const [showApptForm, setShowApptForm] = useState(false)
  const [lovs, setLovs] = useState({ referral_sources: [], religions: [], languages: [] })
  const [consultants, setConsultants] = useState([])
  const [apptTypes, setApptTypes] = useState([])
  const navigate = useNavigate()
  const { token } = useAuth()

  useEffect(() => {
    Promise.all([
      window.ipc.invoke('admin:listLovs', { category: 'referral_source' }),
      window.ipc.invoke('admin:listLovs', { category: 'religion' }),
      window.ipc.invoke('admin:listLovs', { category: 'language' }),
      window.ipc.invoke('admin:listConsultants'),
      window.ipc.invoke('admin:listLovs', { category: 'appointment_type' }),
    ]).then(([rs, rel, lang, cons, types]) => {
      setLovs({ referral_sources: rs, religions: rel, languages: lang })
      setConsultants(cons)
      setApptTypes(types)
    })
    if (!isNew) {
      window.ipc.invoke('patients:get', { id: Number(id) }).then(setPatient)
    }
  }, [id])

  const handleTransition = async (status) => {
    await window.ipc.invoke('patients:transitionStatus', { patientId: patient.id, status, userId: null })
    const updated = await window.ipc.invoke('patients:get', { id: patient.id })
    setPatient(updated)
    setShowStatusMenu(false)
  }

  const handleSaveProfile = async (form) => {
    if (isNew) {
      const p = await window.ipc.invoke('patients:create', { ...form, userId: null })
      navigate(`/queue/${p.id}`, { replace: true })
    } else {
      await window.ipc.invoke('patients:update', { id: patient.id, ...form })
      const updated = await window.ipc.invoke('patients:get', { id: patient.id })
      setPatient(updated)
      setEditingProfile(false)
    }
  }

  const handleSaveAppt = async (form) => {
    await window.ipc.invoke('appointments:create', { patient_id: patient.id, ...form })
    const updated = await window.ipc.invoke('patients:get', { id: patient.id })
    setPatient(updated)
    setShowApptForm(false)
  }

  if (!isNew && !patient) return <div className="loading-screen">Loading…</div>

  return (
    <div className="page">
      <div className="topbar">
        <div className="breadcrumb"><Link to="/queue">Work Queue</Link> › {isNew ? 'New Patient' : `${patient.last_name}, ${patient.first_name}`}</div>
        <div className="topbar-right">
          {!isNew && <button className="btn btn-outline" onClick={() => setEditingProfile(true)}>Edit Profile</button>}
          {!isNew && <button className="btn btn-primary" onClick={() => setShowApptForm(true)}>+ Add Appointment</button>}
        </div>
      </div>

      <div className="detail-layout">
        <div className="detail-left">
          {/* Patient header */}
          {!isNew && (
            <div className="patient-header-card">
              <div className="patient-avatar">{patient.last_name[0]}{patient.first_name[0]}</div>
              <div>
                <div className="patient-name">{patient.last_name}, {patient.first_name} {patient.middle_name || ''}</div>
                <div className="patient-mrn">{patient.mrn || 'No MRN'}</div>
              </div>
              <div className="patient-header-right">
                <StatusBadge status={patient.current_status} />
                <div style={{ position:'relative' }}>
                  <button className="transition-btn" onClick={() => setShowStatusMenu(s => !s)}>Change Status ▾</button>
                  {showStatusMenu && (
                    <div className="status-menu">
                      {STATUSES.filter(s => s !== patient.current_status).map(s => (
                        <button key={s} className="status-menu-item" onClick={() => handleTransition(s)}>
                          <StatusBadge status={s} size="sm" />
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* Profile form / display */}
          <ProfileCard patient={patient} editing={editingProfile} lovs={lovs} onSave={handleSaveProfile} onCancel={() => { setEditingProfile(false); if (isNew) navigate('/queue') }} />

          {/* Status history */}
          {!isNew && patient.statusHistory?.length > 0 && (
            <div className="card">
              <div className="card-header"><h3>Status History</h3></div>
              <div className="card-body">
                {patient.statusHistory.map((h, i) => (
                  <div key={h.id} className="timeline-item">
                    <div className="tl-dot" style={{ background: STATUS_CONFIG[h.status]?.bg, color: STATUS_CONFIG[h.status]?.dot }}>●</div>
                    <div>
                      <div className="tl-status">{STATUS_CONFIG[h.status]?.label || h.status}</div>
                      <div className="tl-meta">{format(new Date(h.changed_at), 'MMM d, yyyy')} · {h.changed_by_name || 'System'}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Appointments panel */}
        {!isNew && (
          <div className="detail-right">
            <div className="card">
              <div className="card-header"><h3>Appointments</h3></div>
              <div className="card-body">
                {patient.appointments?.map(a => (
                  <AppointmentCard key={a.id} appt={a} onUpdate={async (fields) => {
                    await window.ipc.invoke('appointments:update', { id: a.id, ...fields })
                    const updated = await window.ipc.invoke('patients:get', { id: patient.id })
                    setPatient(updated)
                  }} />
                ))}
                {showApptForm && <AppointmentForm consultants={consultants} types={apptTypes} onSave={handleSaveAppt} onCancel={() => setShowApptForm(false)} />}
                {!showApptForm && <button className="add-appt-btn" onClick={() => setShowApptForm(true)}>+ Add Appointment</button>}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function ProfileCard({ patient, editing, lovs, onSave, onCancel }) {
  const [form, setForm] = useState({
    last_name: patient?.last_name || '', first_name: patient?.first_name || '',
    middle_name: patient?.middle_name || '', mrn: patient?.mrn || '',
    phone: patient?.phone || '', date_of_referral: patient?.date_of_referral || '',
    referral_source_id: patient?.referral_source_id || '', religion_id: patient?.religion_id || '',
    language_id: patient?.language_id || ''
  })

  if (!editing && patient) {
    return (
      <div className="card">
        <div className="card-header"><h3>Profile</h3></div>
        <div className="card-body">
          {[['Phone', patient.phone],['Referral Date', patient.date_of_referral],['Referral Source', patient.referral_source],['Religion', patient.religion],['Language', patient.language]].map(([label, value]) => (
            <div key={label} className="field-row">
              <span className="field-label">{label}</span>
              <span className="field-value">{value || '—'}</span>
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="card">
      <div className="card-header"><h3>{patient ? 'Edit Profile' : 'New Patient'}</h3></div>
      <div className="card-body">
        <form onSubmit={e => { e.preventDefault(); onSave(form) }}>
          {[['last_name','Last Name',true],['first_name','First Name',true],['middle_name','Middle Name',false],['mrn','MRN',false],['phone','Phone',false],['date_of_referral','Referral Date',false]].map(([field, label, req]) => (
            <div key={field} className="field">
              <label>{label}{req && ' *'}</label>
              <input type={field === 'date_of_referral' ? 'date' : 'text'} value={form[field]} onChange={e => setForm(f => ({...f, [field]: e.target.value}))} required={req} />
            </div>
          ))}
          {[['referral_source_id','Referral Source', lovs.referral_sources],['religion_id','Religion', lovs.religions],['language_id','Language', lovs.languages]].map(([field, label, options]) => (
            <div key={field} className="field">
              <label>{label}</label>
              <select value={form[field]} onChange={e => setForm(f => ({...f, [field]: e.target.value}))}>
                <option value="">— Select —</option>
                {options.map(o => <option key={o.id} value={o.id}>{o.value}</option>)}
              </select>
            </div>
          ))}
          <div className="form-actions">
            <button type="button" className="btn btn-outline" onClick={onCancel}>Cancel</button>
            <button type="submit" className="btn btn-primary">Save</button>
          </div>
        </form>
      </div>
    </div>
  )
}

function AppointmentCard({ appt, onUpdate }) {
  const APPT_STATUS_COLORS = { scheduled:'#eab308', completed:'#3b82f6', no_show:'#f97316', cancelled:'#ef4444' }
  return (
    <div className="appt-card">
      <div className="appt-date-block">
        <div className="appt-month">{format(new Date(appt.date), 'MMM').toUpperCase()}</div>
        <div className="appt-day">{format(new Date(appt.date), 'd')}</div>
      </div>
      <div className="appt-info">
        <div className="appt-time">{appt.time} · {appt.type_label || 'N/A'}</div>
        <div className="appt-meta">{appt.consultant_name || 'Unassigned'}{appt.is_last_appointment ? ' · ★ Last Appt' : ''}</div>
        {appt.notes && <div className="appt-notes">{appt.notes}</div>}
      </div>
      <div className="appt-right">
        <span style={{ fontSize:10, fontWeight:700, padding:'2px 8px', borderRadius:20, textTransform:'uppercase', background: APPT_STATUS_COLORS[appt.status]+'22', color: APPT_STATUS_COLORS[appt.status] }}>{appt.status.replace('_',' ')}</span>
        <select value={appt.status} onChange={e => onUpdate({ status: e.target.value })} className="appt-status-select">
          {['scheduled','completed','no_show','cancelled'].map(s => <option key={s} value={s}>{s.replace('_',' ')}</option>)}
        </select>
      </div>
    </div>
  )
}

function AppointmentForm({ consultants, types, onSave, onCancel }) {
  const [form, setForm] = useState({ date: '', time: '', type_id: '', consultant_id: '', is_last_appointment: 0, notes: '', status: 'scheduled' })
  return (
    <div className="appt-form">
      <form onSubmit={e => { e.preventDefault(); onSave(form) }}>
        <div className="field-row-inline">
          <div className="field"><label>Date *</label><input type="date" value={form.date} onChange={e => setForm(f => ({...f, date: e.target.value}))} required /></div>
          <div className="field"><label>Time *</label><input type="time" value={form.time} onChange={e => setForm(f => ({...f, time: e.target.value}))} required /></div>
        </div>
        <div className="field"><label>Type</label><select value={form.type_id} onChange={e => setForm(f => ({...f, type_id: e.target.value}))}><option value="">— Select —</option>{types.map(t => <option key={t.id} value={t.id}>{t.value}</option>)}</select></div>
        <div className="field"><label>Consultant</label><select value={form.consultant_id} onChange={e => setForm(f => ({...f, consultant_id: e.target.value}))}><option value="">— Select —</option>{consultants.filter(c => c.is_active).map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></div>
        <div className="field"><label><input type="checkbox" checked={!!form.is_last_appointment} onChange={e => setForm(f => ({...f, is_last_appointment: e.target.checked ? 1 : 0}))} /> Last appointment</label></div>
        <div className="field"><label>Notes</label><textarea value={form.notes} onChange={e => setForm(f => ({...f, notes: e.target.value}))} rows={2} /></div>
        <div className="form-actions">
          <button type="button" className="btn btn-outline" onClick={onCancel}>Cancel</button>
          <button type="submit" className="btn btn-primary">Save Appointment</button>
        </div>
      </form>
    </div>
  )
}
```

- [ ] **Step 2: Verify in app**

```bash
npm run dev
```
Expected: Clicking a patient in Work Queue shows Patient Detail with profile, status history, and appointments. "+ Add Patient" shows blank form.

- [ ] **Step 3: Commit**

```bash
git add src/renderer/pages/PatientDetail.jsx
git commit -m "feat: Patient Detail screen — profile, status transitions, appointments"
```

---

## Task 12: Appointments Day View

**Files:**
- Create: `src/renderer/pages/Appointments.jsx`

- [ ] **Step 1: Write `src/renderer/pages/Appointments.jsx`**

```jsx
import React, { useState, useEffect } from 'react'
import { format, addDays, subDays, parseISO } from 'date-fns'

const APPT_STATUS = {
  scheduled: { bg: '#fefce8', border: '#eab308', label: 'Scheduled' },
  completed: { bg: '#eff6ff', border: '#3b82f6', label: 'Completed' },
  no_show:   { bg: '#fff7ed', border: '#f97316', label: 'No Show' },
  cancelled: { bg: '#fef2f2', border: '#ef4444', label: 'Cancelled' },
}

export default function Appointments() {
  const [date, setDate] = useState(format(new Date(), 'yyyy-MM-dd'))
  const [appointments, setAppointments] = useState([])
  const [daysWithAppts, setDaysWithAppts] = useState([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    const from = format(subDays(new Date(date), 14), 'yyyy-MM-dd')
    const to = format(addDays(new Date(date), 14), 'yyyy-MM-dd')
    window.ipc.invoke('appointments:daysWithAppointments', { from, to }).then(setDaysWithAppts)
  }, [date])

  useEffect(() => {
    setLoading(true)
    window.ipc.invoke('appointments:forDay', { date }).then(list => {
      setAppointments(list)
      setLoading(false)
    })
  }, [date])

  const stripDays = Array.from({ length: 16 }, (_, i) => {
    const d = format(addDays(subDays(new Date(date), 7), i), 'yyyy-MM-dd')
    return { date: d, hasAppts: daysWithAppts.includes(d), isToday: d === format(new Date(), 'yyyy-MM-dd'), isCurrent: d === date }
  })

  // Group appointments by time
  const grouped = appointments.reduce((acc, a) => {
    const key = a.time
    if (!acc[key]) acc[key] = []
    acc[key].push(a)
    return acc
  }, {})
  const times = Object.keys(grouped).sort()

  const counts = ['scheduled','completed','no_show','cancelled'].map(s => ({ status: s, count: appointments.filter(a => a.status === s).length }))

  return (
    <div className="page">
      <div className="topbar">
        <h1>Appointments</h1>
        <div className="topbar-right">
          <button className="btn btn-outline">Export</button>
        </div>
      </div>

      <div className="date-nav">
        <div className="date-nav-arrows">
          <button className="arrow-btn" onClick={() => setDate(format(subDays(new Date(date), 1), 'yyyy-MM-dd'))}>‹</button>
          <button className="arrow-btn" onClick={() => setDate(format(addDays(new Date(date), 1), 'yyyy-MM-dd'))}>›</button>
        </div>
        <div>
          <div className="current-date">{format(parseISO(date), 'EEEE, MMMM d, yyyy')}</div>
          <div className="date-subtitle">{appointments.length} appointment{appointments.length !== 1 ? 's' : ''}</div>
        </div>
        <div className="quick-jumps">
          <button className="jump-btn" onClick={() => setDate(format(subDays(new Date(), 14), 'yyyy-MM-dd'))}>-14 Days</button>
          <button className="jump-btn today" onClick={() => setDate(format(new Date(), 'yyyy-MM-dd'))}>Today</button>
        </div>
      </div>

      <div className="date-strip">
        {stripDays.map(d => (
          <div key={d.date} className={`strip-day${d.isCurrent?' today':''}${d.date < format(new Date(),'yyyy-MM-dd')?' past':''}`} onClick={() => setDate(d.date)}>
            <span className="dow">{format(parseISO(d.date), 'EEE').toUpperCase()}</span>
            <span className="dom">{format(parseISO(d.date), 'd')}</span>
            {d.hasAppts && <div className="appt-dot"></div>}
          </div>
        ))}
      </div>

      <div className="content">
        <div className="day-summary">
          {counts.map(({ status, count }) => (
            <div key={status} className="summary-chip">
              <div className="dot" style={{ background: APPT_STATUS[status].border }}></div>
              <span className="count">{count}</span>
              <span className="label">{APPT_STATUS[status].label}</span>
            </div>
          ))}
        </div>

        {loading ? <div style={{textAlign:'center',padding:32,color:'#a0aec0'}}>Loading…</div>
        : times.length === 0 ? <div style={{textAlign:'center',padding:48,color:'#a0aec0'}}>No appointments for this day</div>
        : times.map(time => (
          <div key={time} className="appt-row">
            <div className="appt-row-time"><span>{format(new Date(`2000-01-01T${time}`), 'h:mm a')}</span></div>
            <div className="appt-cards">
              {grouped[time].map(a => (
                <div key={a.id} className="appt-card" style={{ borderLeftColor: APPT_STATUS[a.status].border, background: APPT_STATUS[a.status].bg }}>
                  <div className="ac-name">{a.last_name}, {a.first_name}</div>
                  <div className="ac-consultant">{a.consultant_name || 'Unassigned'}</div>
                  <div className="ac-tags">
                    {a.type_label && <span className="ac-tag">{a.type_label}</span>}
                    {a.is_last_appointment ? <span className="ac-tag last">★ Last</span> : null}
                    <span className="ac-tag">{APPT_STATUS[a.status].label}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Verify in app — navigate to Appointments, verify day view works**

```bash
npm run dev
```
Expected: Today's appointments show, date strip navigates, -14 Days / Today jump buttons work, appointment cards group by time

- [ ] **Step 3: Commit**

```bash
git add src/renderer/pages/Appointments.jsx
git commit -m "feat: Appointments Day View screen"
```

---

## Task 13: Reports Screen

**Files:**
- Create: `src/renderer/components/BarChart.jsx`
- Create: `src/renderer/components/DateRangePicker.jsx`
- Create: `src/renderer/pages/Reports.jsx`

- [ ] **Step 1: Write `src/renderer/components/DateRangePicker.jsx`**

```jsx
import React from 'react'

export default function DateRangePicker({ from, to, onChange }) {
  return (
    <div className="date-range-picker">
      <input type="date" value={from} onChange={e => onChange({ from: e.target.value, to })} className="date-input" />
      <span className="date-sep">→</span>
      <input type="date" value={to} onChange={e => onChange({ from, to: e.target.value })} className="date-input" />
    </div>
  )
}
```

- [ ] **Step 2: Write `src/renderer/components/BarChart.jsx`**

```jsx
import React from 'react'

export default function BarChart({ rows, labelKey, valueKey, color = '#6366f1' }) {
  const max = Math.max(...rows.map(r => r[valueKey]), 1)
  return (
    <div className="bar-chart">
      {rows.map((row, i) => {
        const pct = Math.round((row[valueKey] / max) * 100)
        const opacity = 1 - (i * 0.15)
        return (
          <div key={i} className="bar-row">
            <span className="bar-label">{row[labelKey]}</span>
            <div className="bar-track">
              <div className="bar-fill" style={{ width: `${pct}%`, background: color, opacity: Math.max(opacity, 0.4) }}>
                {pct > 20 && <span className="bar-val">{row[valueKey]}</span>}
              </div>
              {pct <= 20 && <span className="bar-val-outside">{row[valueKey]}</span>}
            </div>
          </div>
        )
      })}
    </div>
  )
}
```

- [ ] **Step 3: Write `src/renderer/pages/Reports.jsx`**

```jsx
import React, { useState } from 'react'
import { format, startOfMonth, endOfMonth, subMonths } from 'date-fns'
import DateRangePicker from '../components/DateRangePicker'
import BarChart from '../components/BarChart'

const defaultRange = () => ({
  from: format(startOfMonth(subMonths(new Date(), 0)), 'yyyy-MM-dd'),
  to: format(endOfMonth(subMonths(new Date(), 0)), 'yyyy-MM-dd')
})

function ReportCard({ title, desc, channel, renderChart, renderTable, columns }) {
  const [range, setRange] = useState(defaultRange())
  const [results, setResults] = useState(null)
  const [loading, setLoading] = useState(false)

  const run = async () => {
    setLoading(true)
    const data = await window.ipc.invoke(channel, range)
    setResults(data)
    setLoading(false)
  }

  const exportResults = async () => {
    const { filePath } = await window.ipc.invoke('dialog:showSaveDialog', { defaultPath: `${title.replace(/\s+/g,'-')}.xlsx`, filters: [{ name: 'Excel', extensions: ['xlsx'] }] })
    if (filePath) await window.ipc.invoke('excel:exportReport', { filePath, rows: results, sheetName: title })
  }

  return (
    <div className="report-card">
      <div className="report-header">
        <div className="report-title-area">
          <div className="report-title">{title}</div>
          <div className="report-desc">{desc}</div>
        </div>
        <div className="report-controls">
          <DateRangePicker from={range.from} to={range.to} onChange={setRange} />
          <button className="btn-run" onClick={run} disabled={loading}>{loading ? '…' : 'Run'}</button>
          {results && <button className="btn-export" onClick={exportResults}>⬇ Export</button>}
        </div>
      </div>
      {results && (
        <div className="report-body">
          <div className="chart-area">{renderChart(results)}</div>
          <div className="report-divider"></div>
          <div className="table-panel">
            <div className="table-panel-header">
              <span className="table-panel-title">All Results</span>
              <span className="table-row-count">{results.length} rows</span>
            </div>
            <div className="table-scroll">
              <table>
                <thead><tr>{columns.map(c => <th key={c.key} style={c.align==='right'?{textAlign:'right'}:{}}>{c.label}</th>)}</tr></thead>
                <tbody>{renderTable(results)}</tbody>
              </table>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default function Reports() {
  return (
    <div className="page">
      <div className="topbar"><h1>Reports</h1></div>
      <div className="content">

        <ReportCard
          title="Referrals by Source"
          desc="New referrals received, grouped by referral source"
          channel="reports:referralsBySource"
          renderChart={rows => <BarChart rows={rows} labelKey="source" valueKey="count" color="#6366f1" />}
          columns={[{key:'source',label:'Source'},{key:'count',label:'Count',align:'right'},{key:'pct',label:'%',align:'right'}]}
          renderTable={rows => {
            const total = rows.reduce((s, r) => s + r.count, 0)
            return rows.map((r, i) => (
              <tr key={i}><td>{r.source || 'Unknown'}</td><td style={{textAlign:'right',fontWeight:700}}>{r.count}</td><td style={{textAlign:'right',color:'#718096'}}>{total ? Math.round(r.count/total*100) : 0}%</td></tr>
            ))
          }}
        />

        <ReportCard
          title="First Appointments"
          desc="Patients whose first appointment occurred within the date range"
          channel="reports:firstAppointments"
          renderChart={rows => {
            const byWeek = rows.reduce((acc, r) => {
              const week = format(new Date(r.first_appt_date), "'Wk of' MMM d")
              acc[week] = (acc[week] || 0) + 1
              return acc
            }, {})
            return <BarChart rows={Object.entries(byWeek).map(([source,count]) => ({source,count}))} labelKey="source" valueKey="count" color="#22c55e" />
          }}
          columns={[{key:'name',label:'Patient'},{key:'first_appt_date',label:'First Appt'},{key:'consultant_name',label:'Consultant'}]}
          renderTable={rows => rows.map((r, i) => (
            <tr key={i}><td>{r.last_name}, {r.first_name}</td><td style={{color:'#718096',fontSize:11}}>{r.first_appt_date}</td><td style={{color:'#718096'}}>{r.consultant_name || '—'}</td></tr>
          ))}
        />

        <ReportCard
          title="Patients Dropped"
          desc="Patients whose status was changed to Dropped within the date range"
          channel="reports:patientsDropped"
          renderChart={rows => {
            const byWeek = rows.reduce((acc, r) => {
              const week = format(new Date(r.changed_at), "'Wk of' MMM d")
              acc[week] = (acc[week] || 0) + 1
              return acc
            }, {})
            return <BarChart rows={Object.entries(byWeek).map(([source,count]) => ({source,count}))} labelKey="source" valueKey="count" color="#ef4444" />
          }}
          columns={[{key:'name',label:'Patient'},{key:'changed_at',label:'Dropped On'},{key:'changed_by_name',label:'Changed By'}]}
          renderTable={rows => rows.map((r, i) => (
            <tr key={i}><td>{r.last_name}, {r.first_name}</td><td style={{color:'#718096',fontSize:11}}>{r.changed_at?.slice(0,10)}</td><td style={{color:'#718096'}}>{r.changed_by_name || '—'}</td></tr>
          ))}
        />

      </div>
    </div>
  )
}
```

- [ ] **Step 4: Add `dialog:showSaveDialog` handler to `src/main/index.js`**

```js
// Add after existing ipcMain.handle registrations in app.whenReady():
const { dialog } = require('electron')
ipcMain.handle('dialog:showSaveDialog', (_, args) => dialog.showSaveDialog(args))
ipcMain.handle('dialog:showOpenDialog', (_, args) => dialog.showOpenDialog(args))
```

- [ ] **Step 5: Verify in app**

```bash
npm run dev
```
Expected: Reports page renders three cards. After clicking Run, chart and scrollable table appear. Export button writes an xlsx file.

- [ ] **Step 6: Commit**

```bash
git add src/renderer/pages/Reports.jsx src/renderer/components/BarChart.jsx src/renderer/components/DateRangePicker.jsx src/main/index.js
git commit -m "feat: Reports screen — referrals, first appointments, drops with export"
```

---

## Task 14: Admin Screen

**Files:**
- Create: `src/renderer/pages/Admin.jsx`

- [ ] **Step 1: Write `src/renderer/pages/Admin.jsx`**

```jsx
import React, { useState, useEffect } from 'react'

const LOV_CATEGORIES = [
  { key: 'referral_source', label: 'Referral Sources' },
  { key: 'religion', label: 'Religions' },
  { key: 'language', label: 'Languages' },
  { key: 'appointment_type', label: 'Appt Types' },
]

export default function Admin() {
  const [users, setUsers] = useState([])
  const [lovCategory, setLovCategory] = useState('referral_source')
  const [lovs, setLovs] = useState([])
  const [consultants, setConsultants] = useState([])
  const [newUserForm, setNewUserForm] = useState(null)
  const [newLovValue, setNewLovValue] = useState('')
  const [newConsultantName, setNewConsultantName] = useState('')

  const loadUsers = () => window.ipc.invoke('admin:listUsers').then(setUsers)
  const loadLovs = (cat) => window.ipc.invoke('admin:listLovs', { category: cat }).then(setLovs)
  const loadConsultants = () => window.ipc.invoke('admin:listConsultants').then(setConsultants)

  useEffect(() => { loadUsers(); loadConsultants() }, [])
  useEffect(() => { loadLovs(lovCategory) }, [lovCategory])

  const handleCreateUser = async (e) => {
    e.preventDefault()
    await window.ipc.invoke('admin:createUser', newUserForm)
    setNewUserForm(null)
    loadUsers()
  }

  const handleAddLov = async (e) => {
    e.preventDefault()
    if (!newLovValue.trim()) return
    await window.ipc.invoke('admin:upsertLov', { category: lovCategory, value: newLovValue.trim(), sort_order: lovs.length + 1 })
    setNewLovValue('')
    loadLovs(lovCategory)
  }

  const handleAddConsultant = async (e) => {
    e.preventDefault()
    if (!newConsultantName.trim()) return
    await window.ipc.invoke('admin:upsertConsultant', { name: newConsultantName.trim() })
    setNewConsultantName('')
    loadConsultants()
  }

  const initials = (name) => name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase()
  const ROLE_COLORS = { admin: { bg:'#ede9fe', color:'#6d28d9' }, coordinator: { bg:'#f0fdf4', color:'#15803d' } }

  return (
    <div className="page">
      <div className="topbar"><h1>Admin</h1></div>
      <div className="content admin-layout">

        {/* User Management */}
        <div className="panel">
          <div className="panel-header">
            <div><h2>User Management</h2><div className="sub">{users.length} users · {users.filter(u=>u.is_active).length} active</div></div>
            <button className="btn btn-primary" onClick={() => setNewUserForm({ name:'', email:'', password:'', role:'coordinator' })}>+ Add User</button>
          </div>

          {newUserForm && (
            <form className="inline-form" onSubmit={handleCreateUser}>
              {[['name','Name'],['email','Email'],['password','Password']].map(([f,l]) => (
                <div key={f} className="field"><label>{l}</label><input type={f==='password'?'password':f==='email'?'email':'text'} value={newUserForm[f]} onChange={e => setNewUserForm(v => ({...v,[f]:e.target.value}))} required /></div>
              ))}
              <div className="field"><label>Role</label><select value={newUserForm.role} onChange={e => setNewUserForm(v => ({...v, role:e.target.value}))}><option value="coordinator">Coordinator</option><option value="admin">Admin</option></select></div>
              <div className="form-actions"><button type="button" className="btn btn-outline" onClick={() => setNewUserForm(null)}>Cancel</button><button type="submit" className="btn btn-primary">Create</button></div>
            </form>
          )}

          <div className="panel-body">
            {users.map(u => (
              <div key={u.id} className={`user-row${!u.is_active?' inactive':''}`}>
                <div className="user-avatar" style={{ background: u.is_active ? '#6366f1' : '#9ca3af' }}>{initials(u.name)}</div>
                <div className="user-info-col"><div className="user-display-name">{u.name}</div><div className="user-email">{u.email}</div></div>
                <span className="role-badge" style={ROLE_COLORS[u.role]}>{u.role}</span>
                <div className={`status-dot status-${u.is_active?'active':'inactive'}`}></div>
                <div className="user-actions">
                  <button className="btn-sm" onClick={async () => { const pw = prompt('New password:'); if (pw) { await window.ipc.invoke('admin:resetPassword', { id: u.id, newPassword: pw }) } }}>Reset PW</button>
                  <button className={`btn-sm${u.is_active?' btn-danger':''}`} onClick={async () => { await window.ipc.invoke('admin:setUserActive', { id: u.id, is_active: u.is_active ? 0 : 1 }); loadUsers() }}>
                    {u.is_active ? 'Deactivate' : 'Activate'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* List of Values + Consultants */}
        <div className="panel">
          <div className="panel-header"><h2>List of Values</h2></div>
          <div className="lov-tabs">
            {LOV_CATEGORIES.map(c => <button key={c.key} className={`lov-tab${lovCategory===c.key?' active':''}`} onClick={() => setLovCategory(c.key)}>{c.label}</button>)}
            <button className={`lov-tab${lovCategory==='consultant'?' active':''}`} onClick={() => setLovCategory('consultant')}>Consultants</button>
          </div>

          {lovCategory === 'consultant' ? (
            <div className="lov-body">
              <form className="lov-toolbar" onSubmit={handleAddConsultant}>
                <input className="lov-input" placeholder="Add consultant name…" value={newConsultantName} onChange={e => setNewConsultantName(e.target.value)} />
                <button type="submit" className="btn-add">+ Add</button>
              </form>
              <div className="lov-list">
                {consultants.map(c => (
                  <div key={c.id} className="lov-item">
                    <span className={`lov-value${!c.is_active?' lov-inactive':''}`}>{c.name}</span>
                    <div className="lov-actions">
                      <button className="icon-btn" onClick={async () => { await window.ipc.invoke('admin:setConsultantActive', { id: c.id, is_active: c.is_active ? 0 : 1 }); loadConsultants() }}>{c.is_active ? '🗑' : '↩'}</button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div className="lov-body">
              <form className="lov-toolbar" onSubmit={handleAddLov}>
                <input className="lov-input" placeholder={`Add ${LOV_CATEGORIES.find(c=>c.key===lovCategory)?.label.toLowerCase().replace('s','')}…`} value={newLovValue} onChange={e => setNewLovValue(e.target.value)} />
                <button type="submit" className="btn-add">+ Add</button>
              </form>
              <div className="lov-list">
                {lovs.map(l => (
                  <div key={l.id} className="lov-item">
                    <span className="lov-value">{l.value}</span>
                    <div className="lov-actions">
                      <button className="icon-btn danger" onClick={async () => { await window.ipc.invoke('admin:deleteLov', { id: l.id }); loadLovs(lovCategory) }}>🗑</button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

      </div>
    </div>
  )
}
```

- [ ] **Step 2: Verify in app**

```bash
npm run dev
```
Expected: Admin page (visible when logged in as admin) shows Users panel + LoV panel side by side. Add/deactivate users works. Add/remove LoV values works. Consultant tab manages consultants.

- [ ] **Step 3: Commit**

```bash
git add src/renderer/pages/Admin.jsx
git commit -m "feat: Admin screen — user management and List of Values"
```

---

## Task 15: Excel Import UI + Seed LoVs on First Run

**Files:**
- Modify: `src/main/index.js` — call `seedLovs` on first run
- Modify: `src/renderer/pages/Admin.jsx` — add Import button

- [ ] **Step 1: Seed LoVs on first run in `src/main/index.js`**

In `app.whenReady()`, after `runMigrations()`, add:

```js
const { seedLovs } = require('./seed')
const { getDb } = require('./db')
// Only seed if list_of_values is empty
const db = getDb()
const count = db.prepare('SELECT COUNT(*) as n FROM list_of_values').get().n
if (count === 0) seedLovs(db)
```

- [ ] **Step 2: Add Import button to Work Queue**

In `src/renderer/pages/WorkQueue.jsx`, add an Import button to the topbar:

```jsx
const handleImport = async () => {
  const { filePaths } = await window.ipc.invoke('dialog:showOpenDialog', { filters: [{ name: 'Excel', extensions: ['xlsx','xls'] }], properties: ['openFile'] })
  if (!filePaths?.length) return
  const { rows, columns } = await window.ipc.invoke('excel:parseImportFile', { filePath: filePaths[0] })
  // Show a simple column mapping confirmation
  const confirmed = confirm(`Found ${rows.length} rows with columns: ${columns.join(', ')}.\n\nImport with auto-mapping (last_name, first_name, mrn, phone, date_of_referral)?`)
  if (!confirmed) return
  const columnMap = { last_name: 'last_name', first_name: 'first_name', mrn: 'mrn', phone: 'phone', date_of_referral: 'date_of_referral' }
  const result = await window.ipc.invoke('excel:importPatients', { rows, columnMap, userId: null })
  alert(`Imported ${result.imported} patients successfully.`)
  load()
}
```

Add button to topbar in WorkQueue.jsx:
```jsx
<button className="btn btn-outline" onClick={handleImport}>Import Excel</button>
```

- [ ] **Step 3: Verify full flow**

```bash
npm run dev
```
Expected: LoVs pre-populated on first launch. Import Excel button in Work Queue allows selecting an xlsx file and importing patients.

- [ ] **Step 4: Commit**

```bash
git add src/main/index.js src/renderer/pages/WorkQueue.jsx
git commit -m "feat: seed LoVs on first run, Excel import from Work Queue"
```

---

## Task 16: Packaging — Portable Windows Exe

**Files:**
- Create: `assets/icon.ico` *(placeholder — replace with real icon)*
- Modify: `electron-builder.config.js`

- [ ] **Step 1: Install electron-builder**

```bash
npm install --save-dev electron-builder
```

- [ ] **Step 2: Create placeholder icon**

```bash
mkdir -p assets
# Add a 256x256 .ico file at assets/icon.ico
# For development, any .ico will do — use a free icon generator
```

- [ ] **Step 3: Verify full build**

```bash
npm run build
```
Expected: `release/` folder contains `Ambulatory Patients.exe` (portable, ~150MB). Double-clicking it launches the app with no installation required.

- [ ] **Step 4: Test the portable exe**

Run the built exe. Verify:
- First-run screen appears on clean launch
- After creating admin, login works
- Data persists in `%APPDATA%\AmbulatoryPatients\`
- Closing and reopening the exe preserves all data

- [ ] **Step 5: Final commit**

```bash
git add assets/ electron-builder.config.js
git commit -m "feat: electron-builder config for portable Windows exe"
```

---

## Verification Checklist

Run this end-to-end before shipping:

- [ ] `npm test` — all backend tests pass
- [ ] First launch → FirstRun screen → create admin → redirect to Work Queue
- [ ] Add a patient → appears in Work Queue with green "Ready to Schedule" badge
- [ ] Transition patient to Scheduled → badge turns yellow, history timeline updates
- [ ] Add an appointment to the patient → appears on Appointments Day View
- [ ] Run all three reports → charts and scrollable tables render, Export writes xlsx
- [ ] Admin: create coordinator user, log out, log in as coordinator → Admin nav hidden
- [ ] Admin: add a LoV value → appears in patient form dropdown
- [ ] Import Excel → patients appear in Work Queue
- [ ] Build portable exe → runs on Windows without installation
