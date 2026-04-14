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
