// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

// App version + "What's New" state. The renderer can't reach Electron's `app`
// directly, so the current version and last-seen version are exposed over IPC.
// `last_seen_version` lives in app_meta; its absence (or a mismatch with the
// current version) is what triggers the one-time What's New modal after an upgrade.
function createVersionHandlers(db, app) {
  const getMeta = (key) => {
    const row = db.prepare('SELECT value FROM app_meta WHERE key = ?').get(key)
    return row ? row.value : null
  }
  const setMeta = (key, value) => {
    db.prepare(`
      INSERT INTO app_meta (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(key, value)
  }

  return {
    getVersion() {
      return app.getVersion()
    },

    getReleaseStatus() {
      const current = app.getVersion()
      const lastSeen = getMeta('last_seen_version')
      return { current, lastSeen, shouldShowWhatsNew: lastSeen !== current }
    },

    markVersionSeen() {
      const current = app.getVersion()
      setMeta('last_seen_version', current)
      return { ok: true, lastSeen: current }
    }
  }
}

function register(ipcMain, db) {
  const { app } = require('electron')
  const h = createVersionHandlers(db, app)
  ipcMain.handle('app:getVersion', () => h.getVersion())
  ipcMain.handle('app:getReleaseStatus', () => h.getReleaseStatus())
  ipcMain.handle('app:markVersionSeen', () => h.markVersionSeen())
}

module.exports = register
module.exports.createVersionHandlers = createVersionHandlers
