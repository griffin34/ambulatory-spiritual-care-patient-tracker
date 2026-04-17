// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

import React from 'react'

export default function BarChart({ rows, labelKey, valueKey, color = '#6366f1' }) {
  const max = Math.max(...rows.map(r => r[valueKey]), 1)
  return (
    <div className="bar-chart">
      {rows.map((row, i) => {
        const pct = Math.round((row[valueKey] / max) * 100)
        const opacity = 1 - (i * 0.15)
        return (
          <div key={i} className="bar-row">
            <span className="bar-label">{row[labelKey]}</span>
            <div className="bar-track">
              <div className="bar-fill" style={{ width: `${pct}%`, background: color, opacity: Math.max(opacity, 0.4) }}>
                {pct > 20 && <span className="bar-val">{row[valueKey]}</span>}
              </div>
              {pct <= 20 && <span className="bar-val-outside">{row[valueKey]}</span>}
            </div>
          </div>
        )
      })}
    </div>
  )
}
