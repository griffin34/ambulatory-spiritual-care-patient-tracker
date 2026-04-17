// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

function createReportsHandlers(db) {
  return {
    'reports:referralsBySource': (_, args) => {
      const { from, to } = args || {}
      return db.prepare(`
        SELECT
          lov.value AS source,
          COUNT(p.id) AS count
        FROM patients p
        LEFT JOIN list_of_values lov
          ON lov.id = p.referral_source_id AND lov.category = 'referral_source'
        WHERE p.date_of_referral >= ? AND p.date_of_referral <= ?
        GROUP BY p.referral_source_id, lov.value
        ORDER BY count DESC
      `).all(from, to)
    },

    'reports:firstAppointments': (_, args) => {
      const { from, to } = args || {}
      return db.prepare(`
        SELECT
          p.last_name,
          p.first_name,
          a.date AS first_appt_date,
          c.name AS consultant_name
        FROM patients p
        JOIN appointments a ON a.patient_id = p.id
        LEFT JOIN consultants c ON c.id = a.consultant_id
        WHERE a.status IN ('completed', 'scheduled')
          AND a.date = (
            SELECT MIN(a2.date)
            FROM appointments a2
            WHERE a2.patient_id = p.id
              AND a2.status IN ('completed', 'scheduled')
          )
          AND a.date >= ? AND a.date <= ?
        ORDER BY first_appt_date ASC
      `).all(from, to)
    },

    'reports:patientsDropped': (_, args) => {
      const { from, to } = args || {}
      return db.prepare(`
        SELECT
          p.last_name,
          p.first_name,
          h.changed_at,
          u.name AS changed_by_name
        FROM patient_status_history h
        JOIN patients p ON p.id = h.patient_id
        LEFT JOIN users u ON u.id = h.changed_by
        WHERE h.status = 'dropped'
          AND substr(h.changed_at, 1, 10) >= ?
          AND substr(h.changed_at, 1, 10) <= ?
        ORDER BY h.changed_at DESC
      `).all(from, to)
    },
  }
}

function register(ipcMain, db) {
  const handlers = createReportsHandlers(db)
  for (const [channel, handler] of Object.entries(handlers)) {
    ipcMain.handle(channel, handler)
  }
}

module.exports = register
module.exports.createReportsHandlers = createReportsHandlers
