import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { createExcelHandlers } from '../../src/main/ipc/excel.js'
import fs from 'fs'
import os from 'os'
import path from 'path'
import xlsx from 'xlsx'

describe('excel handlers', () => {
  let db, handlers, tmpDir

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

  afterEach(() => {
    db.close()
    fs.rmSync(tmpDir, { recursive: true, force: true })
  })

  // Helper: create a real xlsx file and return its path
  function createXlsxFile(data, filename = 'test.xlsx') {
    const ws = xlsx.utils.aoa_to_sheet(data)
    const wb = xlsx.utils.book_new()
    xlsx.utils.book_append_sheet(wb, ws, 'Sheet1')
    const filePath = path.join(tmpDir, filename)
    xlsx.writeFile(wb, filePath)
    return filePath
  }

  describe('excel:parseImportFile', () => {
    it('returns columns from header row and rows as objects', () => {
      const data = [
        ['last_name', 'first_name', 'mrn', 'phone'],
        ['Smith', 'John', 'MRN001', '555-1234'],
        ['Doe', 'Jane', 'MRN002', '555-5678'],
      ]
      const filePath = createXlsxFile(data)
      const result = handlers['excel:parseImportFile'](null, { filePath })

      expect(result.columns).toEqual(['last_name', 'first_name', 'mrn', 'phone'])
      expect(result.rows).toHaveLength(2)
      expect(result.rows[0]).toMatchObject({ last_name: 'Smith', first_name: 'John', mrn: 'MRN001' })
    })

    it('returns empty rows array for header-only file', () => {
      const data = [['last_name', 'first_name', 'mrn']]
      const filePath = createXlsxFile(data)
      const result = handlers['excel:parseImportFile'](null, { filePath })

      expect(result.columns).toEqual(['last_name', 'first_name', 'mrn'])
      expect(result.rows).toHaveLength(0)
    })

    it('handles files with only one data row', () => {
      const data = [
        ['last_name', 'first_name'],
        ['Garcia', 'Maria'],
      ]
      const filePath = createXlsxFile(data)
      const result = handlers['excel:parseImportFile'](null, { filePath })

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].last_name).toBe('Garcia')
    })
  })

  describe('excel:importPatients', () => {
    const columnMap = {
      last_name: 'last_name',
      first_name: 'first_name',
      mrn: 'mrn',
      phone: 'phone',
      date_of_referral: 'date_of_referral',
    }

    it('inserts patients and returns correct imported count', () => {
      const rows = [
        { last_name: 'Smith', first_name: 'John', mrn: 'MRN001', phone: '555-1111', date_of_referral: '2024-01-01' },
        { last_name: 'Doe', first_name: 'Jane', mrn: 'MRN002', phone: '555-2222', date_of_referral: '2024-01-02' },
      ]
      const result = handlers['excel:importPatients'](null, { rows, columnMap, userId: null })

      expect(result.imported).toBe(2)
      const patients = db.prepare('SELECT * FROM patients').all()
      expect(patients).toHaveLength(2)
    })

    it('creates patient_status_history records with ready_to_schedule for each patient', () => {
      const rows = [
        { last_name: 'Adams', first_name: 'Alice', mrn: 'MRN010' },
      ]
      handlers['excel:importPatients'](null, { rows, columnMap, userId: null })

      const patient = db.prepare('SELECT * FROM patients WHERE last_name = ?').get('Adams')
      const history = db.prepare('SELECT * FROM patient_status_history WHERE patient_id = ?').all(patient.id)
      expect(history).toHaveLength(1)
      expect(history[0].status).toBe('ready_to_schedule')
    })

    it('skips rows missing last_name or first_name', () => {
      const rows = [
        { last_name: 'Good', first_name: 'One', mrn: 'MRN100' },
        { last_name: '', first_name: 'NoLast', mrn: 'MRN101' },
        { last_name: 'NoFirst', first_name: '', mrn: 'MRN102' },
        { mrn: 'MRN103' },
      ]
      const result = handlers['excel:importPatients'](null, { rows, columnMap, userId: null })

      expect(result.imported).toBe(1)
      expect(db.prepare('SELECT COUNT(*) as c FROM patients').get().c).toBe(1)
    })

    it('handles empty rows array gracefully', () => {
      const result = handlers['excel:importPatients'](null, { rows: [], columnMap, userId: null })
      expect(result.imported).toBe(0)
    })
  })

  describe('excel:exportReport', () => {
    it('writes an xlsx file and returns success: true', () => {
      const filePath = path.join(tmpDir, 'report.xlsx')
      const rows = [
        { last_name: 'Smith', first_name: 'John', status: 'ready_to_schedule' },
        { last_name: 'Doe', first_name: 'Jane', status: 'scheduled' },
      ]
      const result = handlers['excel:exportReport'](null, { filePath, rows, sheetName: 'Patients' })

      expect(result).toEqual({ success: true })
      expect(fs.existsSync(filePath)).toBe(true)
    })

    it('writes data that can be read back correctly', () => {
      const filePath = path.join(tmpDir, 'readback.xlsx')
      const rows = [
        { name: 'Alice', value: 42 },
        { name: 'Bob', value: 99 },
      ]
      handlers['excel:exportReport'](null, { filePath, rows, sheetName: 'Data' })

      const wb = xlsx.readFile(filePath)
      const ws = wb.Sheets[wb.SheetNames[0]]
      const parsed = xlsx.utils.sheet_to_json(ws)
      expect(parsed).toHaveLength(2)
      expect(parsed[0]).toMatchObject({ name: 'Alice', value: 42 })
      expect(parsed[1]).toMatchObject({ name: 'Bob', value: 99 })
    })

    it('uses the provided sheetName', () => {
      const filePath = path.join(tmpDir, 'named.xlsx')
      handlers['excel:exportReport'](null, { filePath, rows: [{ x: 1 }], sheetName: 'MyReport' })

      const wb = xlsx.readFile(filePath)
      expect(wb.SheetNames[0]).toBe('MyReport')
    })
  })

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
})
