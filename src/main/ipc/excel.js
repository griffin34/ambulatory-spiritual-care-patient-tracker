// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

const xlsx = require('xlsx')

function createExcelHandlers(db) {
  return {
    'excel:parseImportFile': (_, { filePath }) => {
      const workbook = xlsx.readFile(filePath)
      const sheetName = workbook.SheetNames[0]
      const sheet = workbook.Sheets[sheetName]
      const rows = xlsx.utils.sheet_to_json(sheet)
      const aoa = xlsx.utils.sheet_to_json(sheet, { header: 1 })
      const columns = aoa.length > 0 ? aoa[0].map(String) : []
      return { rows, columns }
    },

    'excel:importPatients': (_, { rows, columnMap, userId }) => {
      const insert = db.prepare(`
        INSERT INTO patients (last_name, first_name, mrn, phone, date_of_referral)
        VALUES (?, ?, ?, ?, ?)
      `)
      const insertHistory = db.prepare(`
        INSERT INTO patient_status_history (patient_id, status, changed_by)
        VALUES (?, 'ready_to_schedule', ?)
      `)

      const map = columnMap || {
        last_name: 'last_name',
        first_name: 'first_name',
        mrn: 'mrn',
        phone: 'phone',
        date_of_referral: 'date_of_referral',
      }

      let imported = 0

      const run = db.transaction(() => {
        for (const row of rows) {
          const last_name = row[map.last_name] || null
          const first_name = row[map.first_name] || null
          if (!last_name || !first_name) continue

          const mrn = row[map.mrn] || null
          const phone = row[map.phone] || null
          const date_of_referral = row[map.date_of_referral] || null

          const { lastInsertRowid } = insert.run(last_name, first_name, mrn, phone, date_of_referral)
          insertHistory.run(lastInsertRowid, userId || null)
          imported++
        }
      })

      run()
      return { imported }
    },

    'excel:importHistorical': (_, { rows }) => {
      const VALID_STATUSES = new Set(['ready_to_schedule', 'scheduled', 'completed', 'dropped', 'on_hold'])
      const VALID_APPT_STATUSES = new Set(['scheduled', 'completed', 'no_show', 'cancelled', 'rescheduled'])

      // Excel date cells arrive as serial numbers (or Date objects); normalize to YYYY-MM-DD
      // so they sort and compare correctly against the date-only strings used everywhere else.
      const toDateStr = (v) => {
        if (v == null || v === '') return null
        if (typeof v === 'number') return xlsx.SSF.format('yyyy-mm-dd', v)
        if (v instanceof Date) {
          const y = v.getFullYear()
          const m = String(v.getMonth() + 1).padStart(2, '0')
          const d = String(v.getDate()).padStart(2, '0')
          return `${y}-${m}-${d}`
        }
        const s = String(v).trim()
        return s || null
      }

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

      // Check which patients already exist: by MRN, and by name for MRN-less records
      const existingPatients = db.prepare('SELECT mrn, last_name, first_name FROM patients').all()
      const existingMrns = new Set(
        existingPatients.filter(p => p.mrn).map(p => p.mrn)
      )
      const nameKey = (last, first) => `name::${String(last || '').trim().toLowerCase()}::${String(first || '').trim().toLowerCase()}`
      const existingNameKeys = new Set(
        existingPatients.filter(p => !p.mrn).map(p => nameKey(p.last_name, p.first_name))
      )

      // Group rows by patient key: prefixed MRN if present, else name-based key
      const patientGroups = new Map()
      for (const row of rows) {
        const last = String(row.last_name || '').trim()
        const first = String(row.first_name || '').trim()
        if (!last || !first) continue
        const mrn = String(row.mrn || '').trim()
        const key = mrn ? `mrn::${mrn}` : nameKey(last, first)
        if (!patientGroups.has(key)) patientGroups.set(key, { mrn, last, first, rows: [] })
        patientGroups.get(key).rows.push(row)
      }
      // Order each patient's rows chronologically so first/last row reflect earliest/latest appt
      for (const group of patientGroups.values()) {
        group.rows.sort((a, b) => String(toDateStr(a.appt_date) || '').localeCompare(String(toDateStr(b.appt_date) || '')))
      }

      const resolveLoV = (category, value) => {
        if (!value) return null
        const s = String(value).trim()
        if (!s) return null
        return lovIndex[`${category}::${s.toLowerCase()}`] ?? null
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
          // Skip if this patient already exists (by MRN, or by name when MRN-less)
          const alreadyExists = group.mrn
            ? existingMrns.has(group.mrn)
            : existingNameKeys.has(nameKey(group.last, group.first))
          if (alreadyExists) {
            patients_skipped++
            continue
          }

          const firstRow = group.rows[0]
          const lastRow = group.rows[group.rows.length - 1]

          const str = (v) => String(v || '').trim()

          const rawStatus = str(lastRow.current_status).toLowerCase()
          const current_status = VALID_STATUSES.has(rawStatus) ? rawStatus : 'ready_to_schedule'

          const { lastInsertRowid: patientId } = insertPatient.run(
            str(firstRow.last_name),
            str(firstRow.first_name),
            str(firstRow.middle_name) || null,
            group.mrn || null,
            str(firstRow.phone) || null,
            toDateStr(firstRow.date_of_referral),
            resolveLoV('referral_source', firstRow.referral_source),
            resolveLoV('religion', firstRow.religion),
            resolveLoV('language', firstRow.language),
            current_status
          )

          insertHistory.run(patientId, current_status)
          patients_imported++

          for (const row of group.rows) {
            const apptDate = toDateStr(row.appt_date)
            if (!apptDate) continue

            const apptTime = str(row.appt_time) || '00:00'
            const typeId = resolveLoV('appointment_type', row.appt_type)
            const consultantId = consultantIndex[str(row.consultant).toLowerCase()] ?? null
            const isLast = str(row.is_last_appointment).toLowerCase() === 'yes' ? 1 : 0
            const rawApptStatus = str(row.appt_status).toLowerCase()
            const apptStatus = VALID_APPT_STATUSES.has(rawApptStatus) ? rawApptStatus : 'scheduled'
            const notes = str(row.notes) || null

            insertAppt.run(patientId, apptDate, apptTime, typeId, consultantId, isLast, apptStatus, notes)
            appointments_imported++
          }
        }
      })

      run()
      return { patients_imported, patients_skipped, appointments_imported }
    },

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

    'excel:exportReport': (_, { filePath, rows, sheetName }) => {
      const ws = xlsx.utils.json_to_sheet(rows)
      const wb = xlsx.utils.book_new()
      xlsx.utils.book_append_sheet(wb, ws, sheetName || 'Sheet1')
      xlsx.writeFile(wb, filePath)
      return { success: true }
    },
  }
}

function register(ipcMain, db) {
  const handlers = createExcelHandlers(db)
  for (const [channel, handler] of Object.entries(handlers)) {
    ipcMain.handle(channel, handler)
  }
}

module.exports = register
module.exports.createExcelHandlers = createExcelHandlers
