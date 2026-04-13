const bcrypt = require('bcryptjs')
const crypto = require('crypto')

// In-memory session store: token -> { userId, role }
const sessions = new Map()

function createAuthHandlers(db) {
  return {
    async checkFirstRun() {
      const count = db.prepare('SELECT COUNT(*) as n FROM users').get().n
      return { needsFirstRun: count === 0 }
    },

    async createFirstAdmin({ name, email, password }) {
      const hash = bcrypt.hashSync(password, 10)
      const { lastInsertRowid } = db.prepare(
        'INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, ?)'
      ).run(name, email, hash, 'admin')
      const user = db.prepare('SELECT id, name, email, role FROM users WHERE id = ?').get(lastInsertRowid)
      const token = crypto.randomUUID()
      sessions.set(token, { userId: user.id, role: user.role })
      return { user, token }
    },

    async login({ email, password }) {
      const user = db.prepare('SELECT * FROM users WHERE email = ? AND is_active = 1').get(email)
      if (!user || !bcrypt.compareSync(password, user.password_hash)) {
        return { error: 'Invalid email or password' }
      }
      const token = crypto.randomUUID()
      sessions.set(token, { userId: user.id, role: user.role })
      return { user: { id: user.id, name: user.name, email: user.email, role: user.role }, token }
    },

    async logout({ token }) {
      sessions.delete(token)
      return { ok: true }
    },

    async getSession({ token }) {
      const session = sessions.get(token)
      if (!session) return { user: null }
      const user = db.prepare('SELECT id, name, email, role FROM users WHERE id = ?').get(session.userId)
      return { user }
    },

    _sessions: sessions
  }
}

function register(ipcMain, db) {
  const h = createAuthHandlers(db)
  ipcMain.handle('auth:checkFirstRun', () => h.checkFirstRun())
  ipcMain.handle('auth:createFirstAdmin', (_, args) => h.createFirstAdmin(args))
  ipcMain.handle('auth:login', (_, args) => h.login(args))
  ipcMain.handle('auth:logout', (_, args) => h.logout(args))
  ipcMain.handle('auth:getSession', (_, args) => h.getSession(args))
}

module.exports = register
module.exports.createAuthHandlers = createAuthHandlers
