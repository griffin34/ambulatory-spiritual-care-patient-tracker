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
        db.prepare('UPDATE list_of_values SET value = ?, sort_order = ? WHERE id = ?').run(value, sort_order || 0, id)
        return db.prepare('SELECT * FROM list_of_values WHERE id = ?').get(id)
      }
      const { lastInsertRowid } = db.prepare('INSERT INTO list_of_values (category, value, sort_order) VALUES (?, ?, ?)').run(category, value, sort_order || 0)
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
