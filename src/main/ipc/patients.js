function createPatientHandlers(db) {
  return {
    async createPatient({ last_name, first_name, middle_name, mrn, phone, date_of_referral, referral_source_id, religion_id, language_id, userId }) {
      const { lastInsertRowid } = db.prepare(`
        INSERT INTO patients (last_name, first_name, middle_name, mrn, phone, date_of_referral, referral_source_id, religion_id, language_id, current_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'ready_to_schedule')
      `).run(last_name, first_name, middle_name||null, mrn||null, phone||null, date_of_referral||null, referral_source_id||null, religion_id||null, language_id||null)

      const userExists = userId ? db.prepare('SELECT id FROM users WHERE id = ?').get(userId) : null
      db.prepare('INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)').run(lastInsertRowid, 'ready_to_schedule', userExists ? userId : null)

      return db.prepare('SELECT * FROM patients WHERE id = ?').get(lastInsertRowid)
    },

    async getPatient({ id }) {
      const patient = db.prepare(`
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
          lang.value as language,
          (SELECT a.date || ' ' || a.time FROM appointments a WHERE a.patient_id = p.id AND a.status = 'scheduled' AND a.date >= date('now') ORDER BY a.date, a.time LIMIT 1) as next_appointment
        FROM patients p
        LEFT JOIN list_of_values rs ON rs.id = p.referral_source_id
        LEFT JOIN list_of_values lang ON lang.id = p.language_id
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
      if (updates.length) {
        const sql = `UPDATE patients SET ${updates.map(([k]) => `${k} = ?`).join(', ')} WHERE id = ?`
        db.prepare(sql).run(...updates.map(([,v]) => v), id)
      }
      return db.prepare(`
        SELECT p.*, rs.value as referral_source, rel.value as religion, lang.value as language
        FROM patients p
        LEFT JOIN list_of_values rs ON rs.id = p.referral_source_id
        LEFT JOIN list_of_values rel ON rel.id = p.religion_id
        LEFT JOIN list_of_values lang ON lang.id = p.language_id
        WHERE p.id = ?
      `).get(id)
    },

    async transitionStatus({ patientId, status, userId }) {
      db.prepare('UPDATE patients SET current_status = ? WHERE id = ?').run(status, patientId)
      const userExists = userId ? db.prepare('SELECT id FROM users WHERE id = ?').get(userId) : null
      db.prepare('INSERT INTO patient_status_history (patient_id, status, changed_by) VALUES (?, ?, ?)').run(patientId, status, userExists ? userId : null)
      return db.prepare(`
        SELECT p.*, rs.value as referral_source, rel.value as religion, lang.value as language
        FROM patients p
        LEFT JOIN list_of_values rs ON rs.id = p.referral_source_id
        LEFT JOIN list_of_values rel ON rel.id = p.religion_id
        LEFT JOIN list_of_values lang ON lang.id = p.language_id
        WHERE p.id = ?
      `).get(patientId)
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
