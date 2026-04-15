# Historical Data Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full historical data import that loads patients and appointments from a flat `.xlsx` template, using the same file format for both the Electron app and the future Excel VBA workbook.

**Architecture:** A new IPC handler `excel:importHistorical` in `src/main/ipc/excel.js` processes a flat `patients_and_appointments` sheet — deduplicating patients by MRN or name, resolving LoV and consultant text values by case-insensitive match, and writing patients + appointments + one status history entry in a single transaction. The Admin page gains an "Import Historical Data" panel with file picker, preview, and result summary. A pre-built template file lives in `docs/patient_import_template.xlsx` and is downloadable from that panel.

**Tech Stack:** Electron IPC, better-sqlite3, xlsx (already in use), React (renderer), Vitest (tests)

---

## File Map

| File | Change |
|------|--------|
| `src/main/ipc/excel.js` | Add `excel:importHistorical` and `excel:generateImportTemplate` handlers |
| `src/renderer/pages/Admin.jsx` | Add "Import Historical Data" panel with file picker, preview, download template button, result summary |
| `tests/main/excel.test.js` | Add tests for `excel:importHistorical` |
| `docs/patient_import_template.xlsx` | New: pre-built template file with headers + one example row |

---

## Task 1: Generate and commit the template file

**Files:**
- Create: `docs/patient_import_template.xlsx`
- Create: `scripts/generate-template.js`

- [ ] **Step 1: Create the generator script**

Create `scripts/generate-template.js`:

```js
const xlsx = require('xlsx')
const path = require('path')

const headers = [
  'last_name', 'first_name', 'middle_name', 'mrn', 'phone',
  'date_of_referral', 'referral_source', 'religion', 'language',
  'current_status', 'appt_date', 'appt_time', 'appt_type',
  'consultant', 'appt_status', 'is_last_appointment', 'notes'
]

const exampleRow = [
  'Smith', 'John', 'A', 'MRN-001', '760-555-0101',
  '2025-01-10', 'Physician Referral', 'Catholic', 'English',
  'completed', '2025-01-24', '10:00', 'Video',
  'Frances', 'completed', 'yes', 'Initial visit completed'
]

const ws = xlsx.utils.aoa_to_sheet([headers, exampleRow])
const wb = xlsx.utils.book_new()
xlsx.utils.book_append_sheet(wb, ws, 'patients_and_appointments')

const outPath = path.join(__dirname, '../docs/patient_import_template.xlsx')
xlsx.writeFile(wb, outPath)
console.log('Template written to', outPath)
```

- [ ] **Step 2: Run the script**

```bash
node scripts/generate-template.js
```

Expected output: `Template written to .../docs/patient_import_template.xlsx`

- [ ] **Step 3: Verify the file**

```bash
node -e "
const xlsx = require('xlsx')
const wb = xlsx.readFile('docs/patient_import_template.xlsx')
console.log('Sheets:', wb.SheetNames)
const ws = wb.Sheets['patients_and_appointments']
const rows = xlsx.utils.sheet_to_json(ws, { header: 1 })
console.log('Headers:', rows[0])
console.log('Example row:', rows[1])
"
```

Expected: SheetNames includes `patients_and_appointments`, 17 headers printed, example row printed.

- [ ] **Step 4: Commit**

```bash
git add docs/patient_import_template.xlsx scripts/generate-template.js
git commit -m "feat: add historical import template xlsx with example row"
```

---

## Task 2: Write failing tests for `excel:importHistorical`

**Files:**
- Modify: `tests/main/excel.test.js`

- [ ] **Step 1: Add the full DB schema to the test `beforeEach`**

The existing `beforeEach` only creates `patients` and `patient_status_history`. Replace the entire `beforeEach` block so all tables exist:

```js
beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  db.exec(`
    CREATE TABLE list_of_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      value TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0,
      UNIQUE(category, value)
    );
    CREATE TABLE consultants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      is_chaplain INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE patients (
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
    CREATE TABLE patient_status_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      status TEXT NOT NULL,
      changed_by INTEGER,
      changed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE appointments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      date TEXT NOT NULL,
      time TEXT NOT NULL,
      type_id INTEGER REFERENCES list_of_values(id),
      consultant_id INTEGER REFERENCES consultants(id),
      is_last_appointment INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'scheduled',
      notes TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `)
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'excel-test-'))
  handlers = createExcelHandlers(db)
})
```

- [ ] **Step 2: Add the `excel:importHistorical` test suite**

Add this block inside the outer `describe('excel handlers', ...)` block, after the existing `excel:exportReport` tests:

```js
describe('excel:importHistorical', () => {
  // Helper: build a flat rows array
  function makeRow(overrides = {}) {
    return {
      last_name: 'Smith',
      first_name: 'John',
      mrn: 'MRN-001',
      phone: '760-555-0101',
      date_of_referral: '2025-01-10',
      referral_source: '',
      religion: '',
      language: '',
      current_status: 'completed',
      appt_date: '',
      appt_time: '',
      appt_type: '',
      consultant: '',
      appt_status: '',
      is_last_appointment: '',
      notes: '',
      ...overrides,
    }
  }

  it('imports a patient-only row and returns correct counts', () => {
    const rows = [makeRow({ appt_date: '' })]
    const result = handlers['excel:importHistorical'](null, { rows })
    expect(result.patients_imported).toBe(1)
    expect(result.patients_skipped).toBe(0)
    expect(result.appointments_imported).toBe(0)
    const patients = db.prepare('SELECT * FROM patients').all()
    expect(patients).toHaveLength(1)
    expect(patients[0].last_name).toBe('Smith')
    expect(patients[0].current_status).toBe('completed')
  })

  it('writes one status history entry per patient', () => {
    const rows = [makeRow()]
    handlers['excel:importHistorical'](null, { rows })
    const patient = db.prepare('SELECT * FROM patients').get()
    const history = db.prepare('SELECT * FROM patient_status_history WHERE patient_id = ?').all(patient.id)
    expect(history).toHaveLength(1)
    expect(history[0].status).toBe('completed')
    expect(history[0].changed_by).toBeNull()
  })

  it('deduplicates by MRN — creates patient once, attaches both appointments', () => {
    const rows = [
      makeRow({ appt_date: '2025-01-20', appt_time: '10:00', appt_status: 'completed' }),
      makeRow({ appt_date: '2025-02-10', appt_time: '11:00', appt_status: 'completed' }),
    ]
    const result = handlers['excel:importHistorical'](null, { rows })
    expect(result.patients_imported).toBe(1)
    expect(result.appointments_imported).toBe(2)
    expect(db.prepare('SELECT COUNT(*) as c FROM patients').get().c).toBe(1)
  })

  it('deduplicates by last+first name when MRN is blank', () => {
    const rows = [
      makeRow({ mrn: '', appt_date: '2025-01-20', appt_time: '10:00' }),
      makeRow({ mrn: '', appt_date: '2025-02-10', appt_time: '11:00' }),
    ]
    const result = handlers['excel:importHistorical'](null, { rows })
    expect(result.patients_imported).toBe(1)
    expect(result.appointments_imported).toBe(2)
  })

  it('skips a patient whose MRN already exists in the DB', () => {
    db.prepare('INSERT INTO patients (last_name, first_name, mrn, current_status) VALUES (?, ?, ?, ?)').run('Smith', 'John', 'MRN-001', 'ready_to_schedule')
    const rows = [makeRow({ appt_date: '2025-01-20', appt_time: '10:00' })]
    const result = handlers['excel:importHistorical'](null, { rows })
    expect(result.patients_imported).toBe(0)
    expect(result.patients_skipped).toBe(1)
    expect(result.appointments_imported).toBe(0)
  })

  it('resolves referral_source to LoV id by case-insensitive match', () => {
    db.prepare("INSERT INTO list_of_values (category, value) VALUES ('referral_source', 'Physician Referral')").run()
    const rows = [makeRow({ referral_source: 'physician referral' })]
    handlers['excel:importHistorical'](null, { rows })
    const patient = db.prepare('SELECT * FROM patients').get()
    expect(patient.referral_source_id).not.toBeNull()
  })

  it('leaves referral_source_id null when LoV value not found', () => {
    const rows = [makeRow({ referral_source: 'Unknown Source' })]
    handlers['excel:importHistorical'](null, { rows })
    const patient = db.prepare('SELECT * FROM patients').get()
    expect(patient.referral_source_id).toBeNull()
  })

  it('resolves consultant by case-insensitive name match', () => {
    db.prepare("INSERT INTO consultants (name) VALUES ('Frances')").run()
    const rows = [makeRow({ appt_date: '2025-01-20', appt_time: '10:00', consultant: 'frances' })]
    handlers['excel:importHistorical'](null, { rows })
    const appt = db.prepare('SELECT * FROM appointments').get()
    expect(appt.consultant_id).not.toBeNull()
  })

  it('leaves consultant_id null when consultant name not found', () => {
    const rows = [makeRow({ appt_date: '2025-01-20', appt_time: '10:00', consultant: 'Nobody' })]
    handlers['excel:importHistorical'](null, { rows })
    const appt = db.prepare('SELECT * FROM appointments').get()
    expect(appt.consultant_id).toBeNull()
  })

  it('maps is_last_appointment "yes" to 1', () => {
    const rows = [makeRow({ appt_date: '2025-01-20', appt_time: '10:00', is_last_appointment: 'yes' })]
    handlers['excel:importHistorical'](null, { rows })
    const appt = db.prepare('SELECT * FROM appointments').get()
    expect(appt.is_last_appointment).toBe(1)
  })

  it('maps is_last_appointment anything else to 0', () => {
    const rows = [makeRow({ appt_date: '2025-01-20', appt_time: '10:00', is_last_appointment: 'no' })]
    handlers['excel:importHistorical'](null, { rows })
    const appt = db.prepare('SELECT * FROM appointments').get()
    expect(appt.is_last_appointment).toBe(0)
  })

  it('uses current_status from the last row for a patient', () => {
    const rows = [
      makeRow({ current_status: 'scheduled', appt_date: '2025-01-20', appt_time: '10:00' }),
      makeRow({ current_status: 'completed', appt_date: '2025-02-10', appt_time: '11:00' }),
    ]
    handlers['excel:importHistorical'](null, { rows })
    const patient = db.prepare('SELECT * FROM patients').get()
    expect(patient.current_status).toBe('completed')
  })

  it('defaults current_status to ready_to_schedule when blank', () => {
    const rows = [makeRow({ current_status: '' })]
    handlers['excel:importHistorical'](null, { rows })
    const patient = db.prepare('SELECT * FROM patients').get()
    expect(patient.current_status).toBe('ready_to_schedule')
  })

  it('skips rows missing last_name or first_name', () => {
    const rows = [
      { last_name: '', first_name: 'NoLast', mrn: 'X1', current_status: '', appt_date: '' },
      { last_name: 'NoFirst', first_name: '', mrn: 'X2', current_status: '', appt_date: '' },
    ]
    const result = handlers['excel:importHistorical'](null, { rows })
    expect(result.patients_imported).toBe(0)
    expect(db.prepare('SELECT COUNT(*) as c FROM patients').get().c).toBe(0)
  })

  it('handles empty rows array', () => {
    const result = handlers['excel:importHistorical'](null, { rows: [] })
    expect(result.patients_imported).toBe(0)
    expect(result.patients_skipped).toBe(0)
    expect(result.appointments_imported).toBe(0)
  })
})
```

- [ ] **Step 3: Run the tests to confirm they fail**

```bash
npm test
```

Expected: all `excel:importHistorical` tests fail with "is not a function" or similar — handler doesn't exist yet.

- [ ] **Step 4: Commit the failing tests**

```bash
git add tests/main/excel.test.js
git commit -m "test: add failing tests for excel:importHistorical"
```

---

## Task 3: Implement `excel:importHistorical`

**Files:**
- Modify: `src/main/ipc/excel.js`

- [ ] **Step 1: Add the handler to `createExcelHandlers`**

Open `src/main/ipc/excel.js`. After the `'excel:importPatients'` handler (line 53), add the following handler inside the returned object:

```js
'excel:importHistorical': (_, { rows }) => {
  const VALID_STATUSES = new Set(['ready_to_schedule', 'scheduled', 'completed', 'dropped', 'on_hold'])
  const VALID_APPT_STATUSES = new Set(['scheduled', 'completed', 'no_show', 'cancelled', 'rescheduled'])

  // Load LoV and consultants once for resolution
  const lovRows = db.prepare('SELECT id, category, value FROM list_of_values WHERE is_active = 1').all()
  const lovIndex = {}
  for (const lov of lovRows) {
    const key = `${lov.category}::${lov.value.toLowerCase()}`
    lovIndex[key] = lov.id
  }

  const consultantRows = db.prepare('SELECT id, name FROM consultants WHERE is_active = 1').all()
  const consultantIndex = {}
  for (const c of consultantRows) {
    consultantIndex[c.name.toLowerCase()] = c.id
  }

  // Check which MRNs already exist
  const existingMrns = new Set(
    db.prepare('SELECT mrn FROM patients WHERE mrn IS NOT NULL AND mrn != ""').all().map(r => r.mrn)
  )

  // Group rows by patient key: MRN if present, else "last_name::first_name"
  const patientGroups = new Map()
  for (const row of rows) {
    const last = (row.last_name || '').trim()
    const first = (row.first_name || '').trim()
    if (!last || !first) continue
    const mrn = (row.mrn || '').trim()
    const key = mrn || `${last.toLowerCase()}::${first.toLowerCase()}`
    if (!patientGroups.has(key)) patientGroups.set(key, { mrn, rows: [] })
    patientGroups.get(key).rows.push(row)
  }

  const insertPatient = db.prepare(`
    INSERT INTO patients (last_name, first_name, middle_name, mrn, phone, date_of_referral,
      referral_source_id, religion_id, language_id, current_status)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `)
  const insertHistory = db.prepare(`
    INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, NULL)
  `)
  const insertAppt = db.prepare(`
    INSERT INTO appointments (patient_id, date, time, type_id, consultant_id,
      is_last_appointment, status, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `)

  let patients_imported = 0
  let patients_skipped = 0
  let appointments_imported = 0

  const run = db.transaction(() => {
    for (const [, group] of patientGroups) {
      // Skip if MRN already in DB
      if (group.mrn && existingMrns.has(group.mrn)) {
        patients_skipped++
        continue
      }

      const firstRow = group.rows[0]
      const lastRow = group.rows[group.rows.length - 1]

      const resolveLoV = (category, value) => {
        if (!value || !value.trim()) return null
        return lovIndex[`${category}::${value.trim().toLowerCase()}`] ?? null
      }

      const rawStatus = (lastRow.current_status || '').trim().toLowerCase()
      const current_status = VALID_STATUSES.has(rawStatus) ? rawStatus : 'ready_to_schedule'

      const { lastInsertRowid: patientId } = insertPatient.run(
        firstRow.last_name.trim(),
        firstRow.first_name.trim(),
        (firstRow.middle_name || '').trim() || null,
        group.mrn || null,
        (firstRow.phone || '').trim() || null,
        (firstRow.date_of_referral || '').trim() || null,
        resolveLoV('referral_source', firstRow.referral_source),
        resolveLoV('religion', firstRow.religion),
        resolveLoV('language', firstRow.language),
        current_status
      )

      insertHistory.run(patientId, current_status)
      patients_imported++

      for (const row of group.rows) {
        const apptDate = (row.appt_date || '').trim()
        if (!apptDate) continue

        const apptTime = (row.appt_time || '').trim() || '00:00'
        const typeId = resolveLoV('appointment_type', row.appt_type)
        const consultantId = consultantIndex[(row.consultant || '').trim().toLowerCase()] ?? null
        const isLast = (row.is_last_appointment || '').trim().toLowerCase() === 'yes' ? 1 : 0
        const rawApptStatus = (row.appt_status || '').trim().toLowerCase()
        const apptStatus = VALID_APPT_STATUSES.has(rawApptStatus) ? rawApptStatus : 'scheduled'
        const notes = (row.notes || '').trim() || null

        insertAppt.run(patientId, apptDate, apptTime, typeId, consultantId, isLast, apptStatus, notes)
        appointments_imported++
      }
    }
  })

  run()
  return { patients_imported, patients_skipped, appointments_imported }
},
```

- [ ] **Step 2: Run tests to confirm they pass**

```bash
npm test
```

Expected: all `excel:importHistorical` tests pass. All existing tests continue to pass.

- [ ] **Step 3: Commit**

```bash
git add src/main/ipc/excel.js
git commit -m "feat: implement excel:importHistorical IPC handler"
```

---

## Task 4: Add `excel:generateImportTemplate` handler

**Files:**
- Modify: `src/main/ipc/excel.js`

This handler lets the UI trigger a "Download Template" that writes the template to a user-chosen path.

- [ ] **Step 1: Add the handler inside `createExcelHandlers`**

After `excel:importHistorical`, add:

```js
'excel:generateImportTemplate': (_, { filePath }) => {
  const headers = [
    'last_name', 'first_name', 'middle_name', 'mrn', 'phone',
    'date_of_referral', 'referral_source', 'religion', 'language',
    'current_status', 'appt_date', 'appt_time', 'appt_type',
    'consultant', 'appt_status', 'is_last_appointment', 'notes'
  ]
  const exampleRow = [
    'Smith', 'John', 'A', 'MRN-001', '760-555-0101',
    '2025-01-10', 'Physician Referral', 'Catholic', 'English',
    'completed', '2025-01-24', '10:00', 'Video',
    'Frances', 'completed', 'yes', 'Initial visit completed'
  ]
  const ws = xlsx.utils.aoa_to_sheet([headers, exampleRow])
  const wb = xlsx.utils.book_new()
  xlsx.utils.book_append_sheet(wb, ws, 'patients_and_appointments')
  xlsx.writeFile(wb, filePath)
  return { success: true }
},
```

- [ ] **Step 2: Run tests to confirm nothing broke**

```bash
npm test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/main/ipc/excel.js
git commit -m "feat: add excel:generateImportTemplate handler"
```

---

## Task 5: Add "Import Historical Data" panel to Admin page

**Files:**
- Modify: `src/renderer/pages/Admin.jsx`

- [ ] **Step 1: Add state for the import panel**

At the top of the `Admin` function, after the existing `useState` declarations, add:

```js
const [importState, setImportState] = useState('idle') // 'idle' | 'preview' | 'importing' | 'done'
const [importPreview, setImportPreview] = useState(null) // { rows, patientCount, apptCount }
const [importResult, setImportResult] = useState(null)  // { patients_imported, patients_skipped, appointments_imported }
```

- [ ] **Step 2: Add the file-pick + preview handler**

After the existing `handleAddConsultant` function, add:

```js
const handlePickImportFile = async () => {
  const { canceled, filePaths } = await window.ipc.invoke('dialog:showOpenDialog', {
    title: 'Select Historical Import File',
    filters: [{ name: 'Excel Files', extensions: ['xlsx'] }],
    properties: ['openFile'],
  })
  if (canceled || !filePaths.length) return

  const { rows } = await window.ipc.invoke('excel:parseImportFile', { filePath: filePaths[0] })

  // Detect patient groups for preview count
  const seen = new Set()
  let patientCount = 0
  let apptCount = 0
  for (const row of rows) {
    const last = (row.last_name || '').trim()
    const first = (row.first_name || '').trim()
    if (!last || !first) continue
    const mrn = (row.mrn || '').trim()
    const key = mrn || `${last.toLowerCase()}::${first.toLowerCase()}`
    if (!seen.has(key)) { seen.add(key); patientCount++ }
    if ((row.appt_date || '').trim()) apptCount++
  }

  setImportPreview({ rows, patientCount, apptCount })
  setImportState('preview')
}

const handleConfirmImport = async () => {
  if (!importPreview) return
  setImportState('importing')
  const result = await window.ipc.invoke('excel:importHistorical', { rows: importPreview.rows })
  setImportResult(result)
  setImportState('done')
}

const handleDownloadTemplate = async () => {
  const { canceled, filePath } = await window.ipc.invoke('dialog:showSaveDialog', {
    title: 'Save Import Template',
    defaultPath: 'patient_import_template.xlsx',
    filters: [{ name: 'Excel Files', extensions: ['xlsx'] }],
  })
  if (canceled || !filePath) return
  await window.ipc.invoke('excel:generateImportTemplate', { filePath })
}

const handleResetImport = () => {
  setImportState('idle')
  setImportPreview(null)
  setImportResult(null)
}
```

- [ ] **Step 3: Add the import panel JSX**

Inside the `return` block, after the closing `</div>` of the List of Values panel (before the closing `</div>` of `admin-layout`), add:

```jsx
<div className="panel">
  <div className="panel-header">
    <div>
      <h2>Import Historical Data</h2>
      <div className="sub">Load patients and appointments from the standard import template</div>
    </div>
    <button className="btn btn-outline" onClick={handleDownloadTemplate}>Download Template</button>
  </div>

  {importState === 'idle' && (
    <div className="panel-body import-idle">
      <p className="import-hint">Select a filled-in template file to preview before importing.</p>
      <button className="btn btn-primary" onClick={handlePickImportFile}>Select File…</button>
    </div>
  )}

  {importState === 'preview' && importPreview && (
    <div className="panel-body import-preview">
      <div className="import-counts">
        <div className="import-count-item"><span className="import-count-num">{importPreview.patientCount}</span><span className="import-count-label">patients detected</span></div>
        <div className="import-count-item"><span className="import-count-num">{importPreview.apptCount}</span><span className="import-count-label">appointments detected</span></div>
      </div>
      <p className="import-hint">Patients whose MRN already exists in the database will be skipped.</p>
      <div className="form-actions">
        <button className="btn btn-outline" onClick={handleResetImport}>Cancel</button>
        <button className="btn btn-primary" onClick={handleConfirmImport}>Import</button>
      </div>
    </div>
  )}

  {importState === 'importing' && (
    <div className="panel-body import-idle"><p className="import-hint">Importing…</p></div>
  )}

  {importState === 'done' && importResult && (
    <div className="panel-body import-done">
      <div className="import-counts">
        <div className="import-count-item"><span className="import-count-num">{importResult.patients_imported}</span><span className="import-count-label">patients imported</span></div>
        <div className="import-count-item"><span className="import-count-num">{importResult.patients_skipped}</span><span className="import-count-label">patients skipped</span></div>
        <div className="import-count-item"><span className="import-count-num">{importResult.appointments_imported}</span><span className="import-count-label">appointments imported</span></div>
      </div>
      <button className="btn btn-outline" onClick={handleResetImport}>Import Another File</button>
    </div>
  )}
</div>
```

- [ ] **Step 4: Commit**

```bash
git add src/renderer/pages/Admin.jsx
git commit -m "feat: add historical import panel to Admin page"
```

---

## Task 6: Add CSS for import panel

**Files:**
- Modify: `src/renderer/styles/globals.css`

- [ ] **Step 1: Append import panel styles**

Open `src/renderer/styles/globals.css` and add at the end of the file:

```css
/* Import panel */
.import-idle {
  display: flex;
  flex-direction: column;
  gap: 12px;
  align-items: flex-start;
}

.import-hint {
  font-size: 13px;
  color: var(--text-muted, #6b7280);
  margin: 0;
}

.import-preview,
.import-done {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.import-counts {
  display: flex;
  gap: 24px;
}

.import-count-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
}

.import-count-num {
  font-size: 28px;
  font-weight: 700;
  color: var(--primary, #6366f1);
  line-height: 1;
}

.import-count-label {
  font-size: 11px;
  color: var(--text-muted, #6b7280);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
```

- [ ] **Step 2: Start the dev server and verify the import panel renders correctly**

```bash
npm run dev
```

Navigate to Admin page. Verify:
- "Import Historical Data" panel is visible with "Download Template" button
- "Select File…" button is visible
- Clicking "Download Template" opens a save dialog
- Clicking "Select File…" opens a file picker
- After selecting the template file from `docs/patient_import_template.xlsx`, the preview shows `1 patients detected, 1 appointments detected`
- Clicking Import shows the result summary

- [ ] **Step 3: Commit**

```bash
git add src/renderer/styles/globals.css
git commit -m "feat: add CSS for historical import panel"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| Flat `patients_and_appointments` sheet | Template Task 1 |
| 17 columns as specified | Task 1 + Task 3 |
| Deduplicate by MRN then last+first name | Task 3 |
| Skip existing MRNs (count as skipped) | Task 3 |
| LoV resolution case-insensitive, null if no match | Task 3 |
| Consultant resolution case-insensitive, null if no match | Task 3 |
| current_status from last row, default ready_to_schedule | Task 3 |
| One status history entry per patient, changed_by null | Task 3 |
| appt_status default 'scheduled' | Task 3 |
| is_last_appointment 'yes'→1, else→0 | Task 3 |
| Return patients_imported, patients_skipped, appointments_imported | Task 3 |
| All in one DB transaction | Task 3 |
| Template download button | Task 4 + Task 5 |
| UI preview (patient/appt count before confirming) | Task 5 |
| Result summary after import | Task 5 |
| Shared template for Electron + future Excel VBA | Template file in Task 1, noted in spec |

**Placeholder scan:** No TBDs, TODOs, or vague steps found.

**Type consistency:** `createExcelHandlers` is the only export pattern used throughout. `xlsx` is already imported at the top of `excel.js`. All handler keys follow the `excel:*` convention.
