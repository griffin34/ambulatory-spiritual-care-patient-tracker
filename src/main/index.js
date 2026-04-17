// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

const { app, BrowserWindow, ipcMain, Menu } = require('electron')
const path = require('path')
const { runMigrations, getDb } = require('./db')
const { seedLovs } = require('./seed')
const registerAuth = require('./ipc/auth')
const registerPatients = require('./ipc/patients')
const registerAppointments = require('./ipc/appointments')
const registerReports = require('./ipc/reports')
const registerAdmin = require('./ipc/admin')
const registerExcel = require('./ipc/excel')

const isDev = process.env.NODE_ENV === 'development'

function createWindow() {
  const win = new BrowserWindow({
    width: 1280, height: 800,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  })
  if (isDev) {
    win.loadURL('http://localhost:5173')
  } else {
    win.loadFile(path.join(__dirname, '../../dist/renderer/index.html'))
  }
}

app.whenReady().then(() => {
  runMigrations()
  const db = getDb()
  seedLovs(db)
  registerAuth(ipcMain, db)
  registerPatients(ipcMain, db)
  registerAppointments(ipcMain, db)
  registerReports(ipcMain, db)
  registerAdmin(ipcMain, db)
  registerExcel(ipcMain, db)
  const { dialog } = require('electron')
  ipcMain.handle('dialog:showSaveDialog', (_, args) => dialog.showSaveDialog(args))
  ipcMain.handle('dialog:showOpenDialog', (_, args) => dialog.showOpenDialog(args))
  app.setAboutPanelOptions({ applicationName: 'Ambulatory Patients', applicationVersion: app.getVersion() })
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: 'Help', submenu: [{ label: 'About', click: () => app.showAboutPanel() }] }
  ]))
  createWindow()
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
