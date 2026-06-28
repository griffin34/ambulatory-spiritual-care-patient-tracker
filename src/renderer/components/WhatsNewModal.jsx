// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

import React, { useEffect, useState } from 'react'
import { RELEASE_NOTES } from '../releaseNotes'

// Shows the release notes once after an upgrade. The main process reports
// whether the current version differs from the last-seen version; dismissing
// records the current version so it won't show again.
export default function WhatsNewModal() {
  const [show, setShow] = useState(false)

  useEffect(() => {
    window.ipc.invoke('app:getReleaseStatus').then(status => {
      if (status?.shouldShowWhatsNew) setShow(true)
    })
  }, [])

  const dismiss = async () => {
    await window.ipc.invoke('app:markVersionSeen')
    setShow(false)
  }

  if (!show) return null

  return (
    <div className="modal-overlay no-print" onClick={dismiss}>
      <div className="modal-card" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <h2>What's New</h2>
          <span className="modal-version">v{RELEASE_NOTES.version}</span>
        </div>
        <ul className="whats-new-list">
          {RELEASE_NOTES.highlights.map((h, i) => <li key={i}>{h}</li>)}
        </ul>
        <div className="form-actions">
          <button className="btn btn-primary" onClick={dismiss}>Got it</button>
        </div>
      </div>
    </div>
  )
}
