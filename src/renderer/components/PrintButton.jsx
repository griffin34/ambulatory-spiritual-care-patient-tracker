// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

import React from 'react'

// Different screens need different print orientation (wide tables print best
// landscape; the patient detail report reads better portrait). @page rules
// are global, so we override the page size just before printing rather than
// relying on a single static default that would leak across pages.
function setPrintOrientation(orientation) {
  let style = document.getElementById('print-orientation')
  if (!style) {
    style = document.createElement('style')
    style.id = 'print-orientation'
    document.head.appendChild(style)
  }
  style.textContent = `@media print { @page { size: ${orientation}; margin: 10mm; } }`
}

// Triggers the browser/Electron print dialog. Page chrome is hidden via the
// @media print rules in styles/globals.css.
export default function PrintButton({ label = 'Print', orientation = 'landscape' }) {
  return (
    <button className="btn btn-outline no-print" onClick={() => { setPrintOrientation(orientation); window.print() }}>
      🖨 {label}
    </button>
  )
}
