// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

// SDAT scores are integers 0–40; empty/unset becomes null. NOTE: do not use the
// generic `v || null` for scores — 0 is a valid score that would be wrongly dropped.
function coerceSdatScore(v) {
  if (v === '' || v === null || v === undefined) return null
  const n = typeof v === 'number' ? v : parseInt(v, 10)
  if (!Number.isInteger(n) || n < 0 || n > 40) throw new Error('SDAT score must be an integer between 0 and 40')
  return n
}

// Patient notes: free text, max 256 characters; empty/unset becomes null.
function coerceNotes(v) {
  if (v === '' || v === null || v === undefined) return null
  const s = String(v)
  if (s.length > 256) throw new Error('Notes must be 256 characters or fewer')
  return s
}

// Stored on the patient (not recomputed per-report) so reports never need to
// recalculate it. SDAT is a distress score, so lower is better: a positive
// result means distress decreased. Null when either score is missing or the
// begin score is 0 (divide-by-zero).
function computeSdatPct(beginScore, endScore) {
  if (beginScore == null || endScore == null || beginScore === 0) return null
  return Math.round((beginScore - endScore) * 1000 / beginScore) / 10
}

function createPatientHandlers(db) {
  const getPatientById = (id) => db.prepare(`
    SELECT p.*,
      rs.value as referral_source,
      rel.value as religion,
      lang.value as language
    FROM patients p
    LEFT JOIN list_of_values rs ON rs.id = p.referral_source_id
    LEFT JOIN list_of_values rel ON rel.id = p.religion_id
    LEFT JOIN list_of_values lang ON lang.id = p.language_id
    WHERE p.id = ?
  `).get(id)

  return {
    async createPatient({ last_name, first_name, middle_name, mrn, phone, date_of_referral, referral_source_id, religion_id, language_id, sdat_begin_score, sdat_begin_date, sdat_end_score, sdat_end_date, notes, userId }) {
      const beginScore = coerceSdatScore(sdat_begin_score)
      const endScore = coerceSdatScore(sdat_end_score)
      const { lastInsertRowid } = db.prepare(`
        INSERT INTO patients (last_name, first_name, middle_name, mrn, phone, date_of_referral, referral_source_id, religion_id, language_id, current_status, sdat_begin_score, sdat_begin_date, sdat_end_score, sdat_end_date, sdat_pct_improvement, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'ready_to_schedule', ?, ?, ?, ?, ?, ?)
      `).run(last_name, first_name, middle_name||null, mrn||null, phone||null, date_of_referral||null, referral_source_id||null, religion_id||null, language_id||null, beginScore, sdat_begin_date||null, endScore, sdat_end_date||null, computeSdatPct(beginScore, endScore), coerceNotes(notes))

      const userExists = userId ? db.prepare('SELECT id FROM users WHERE id = ?').get(userId) : null
      db.prepare('INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)').run(lastInsertRowid, 'ready_to_schedule', userExists ? userId : null)

      return db.prepare('SELECT * FROM patients WHERE id = ?').get(lastInsertRowid)
    },

    async getPatient({ id }) {
      const patient = getPatientById(id)
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

    async listPatients({ status, referral_source_id, search, includeDeleted } = {}) {
      let sql = `
        SELECT p.*, rs.value as referral_source,
          rel.value as religion,
          lang.value as language,
          (SELECT a.date || ' ' || a.time FROM appointments a WHERE a.patient_id = p.id AND a.status = 'scheduled' AND a.date >= date('now') ORDER BY a.date, a.time LIMIT 1) as next_appointment
        FROM patients p
        LEFT JOIN list_of_values rs ON rs.id = p.referral_source_id
        LEFT JOIN list_of_values rel ON rel.id = p.religion_id
        LEFT JOIN list_of_values lang ON lang.id = p.language_id
        WHERE 1=1
      `
      const params = []
      if (status === 'deleted') {
        // Soft-deleted patients (is_active=0); shown only when explicitly requested.
        sql += " AND p.current_status = 'deleted'"
      } else if (status) {
        sql += ' AND p.current_status = ? AND p.is_active = 1'; params.push(status)
      } else if (!includeDeleted) {
        sql += ' AND p.is_active = 1'
      }
      if (referral_source_id) { sql += ' AND p.referral_source_id = ?'; params.push(referral_source_id) }
      if (search) { sql += ' AND (p.last_name LIKE ? OR p.first_name LIKE ? OR p.mrn LIKE ?)'; params.push(`%${search}%`, `%${search}%`, `%${search}%`) }
      sql += ' ORDER BY p.date_of_referral ASC'
      return db.prepare(sql).all(...params)
    },

    async updatePatient({ id, ...fields }) {
      const allowed = ['last_name','first_name','middle_name','mrn','phone','date_of_referral','referral_source_id','religion_id','language_id','sdat_begin_score','sdat_begin_date','sdat_end_score','sdat_end_date','notes']
      const nullable = ['middle_name','mrn','phone','date_of_referral','referral_source_id','religion_id','language_id','sdat_begin_date','sdat_end_date']
      const coerce = (k, v) => {
        if (k === 'sdat_begin_score' || k === 'sdat_end_score') return coerceSdatScore(v)
        if (k === 'notes') return coerceNotes(v)
        return nullable.includes(k) ? (v || null) : v
      }
      const updates = Object.entries(fields).filter(([k]) => allowed.includes(k))
        .map(([k, v]) => [k, coerce(k, v)])

      // Keep the stored % improvement in sync whenever either score changes,
      // merging in whichever score wasn't part of this particular update.
      if (updates.some(([k]) => k === 'sdat_begin_score' || k === 'sdat_end_score')) {
        const current = db.prepare('SELECT sdat_begin_score, sdat_end_score FROM patients WHERE id = ?').get(id)
        const updateMap = Object.fromEntries(updates)
        const beginScore = 'sdat_begin_score' in updateMap ? updateMap.sdat_begin_score : current.sdat_begin_score
        const endScore = 'sdat_end_score' in updateMap ? updateMap.sdat_end_score : current.sdat_end_score
        updates.push(['sdat_pct_improvement', computeSdatPct(beginScore, endScore)])
      }

      if (updates.length) {
        const sql = `UPDATE patients SET ${updates.map(([k]) => `${k} = ?`).join(', ')} WHERE id = ?`
        db.prepare(sql).run(...updates.map(([,v]) => v), id)
      }
      return getPatientById(id)
    },

    async transitionStatus({ patientId, status, userId }) {
      db.prepare('UPDATE patients SET current_status = ? WHERE id = ?').run(status, patientId)
      const userExists = userId ? db.prepare('SELECT id FROM users WHERE id = ?').get(userId) : null
      db.prepare('INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)').run(patientId, status, userExists ? userId : null)
      return getPatientById(patientId)
    },

    // Soft delete: mark deleted + inactive (hidden from the default queue), append history.
    async deletePatient({ patientId, userId }) {
      db.prepare("UPDATE patients SET current_status = 'deleted', is_active = 0 WHERE id = ?").run(patientId)
      const userExists = userId ? db.prepare('SELECT id FROM users WHERE id = ?').get(userId) : null
      db.prepare('INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)').run(patientId, 'deleted', userExists ? userId : null)
      return getPatientById(patientId)
    },

    // Restore a soft-deleted patient back into the active workflow (default: on hold).
    async restorePatient({ patientId, userId, status = 'on_hold' }) {
      db.prepare('UPDATE patients SET current_status = ?, is_active = 1 WHERE id = ?').run(status, patientId)
      const userExists = userId ? db.prepare('SELECT id FROM users WHERE id = ?').get(userId) : null
      db.prepare('INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)').run(patientId, status, userExists ? userId : null)
      return getPatientById(patientId)
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
  ipcMain.handle('patients:delete', (_, args) => h.deletePatient(args))
  ipcMain.handle('patients:restore', (_, args) => h.restorePatient(args))
}

module.exports = register
module.exports.createPatientHandlers = createPatientHandlers
