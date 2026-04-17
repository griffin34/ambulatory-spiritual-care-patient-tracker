// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('ipc', {
  invoke: (channel, args) => ipcRenderer.invoke(channel, args)
})
