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
