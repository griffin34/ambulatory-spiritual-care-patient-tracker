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
    db.exec(`CREATE TABLE patients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      last_name TEXT NOT NULL,
      first_name TEXT NOT NULL,
      mrn TEXT,
      phone TEXT,
      date_of_referral TEXT
    )`)
    db.exec(`CREATE TABLE patient_status_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES patients(id),
      status TEXT NOT NULL,
      changed_at TEXT NOT NULL DEFAULT (datetime('now')),
      changed_by INTEGER
    )`)
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
})
