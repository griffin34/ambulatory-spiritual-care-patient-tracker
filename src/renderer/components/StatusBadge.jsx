// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

const STATUS_CONFIG = {
  ready_to_schedule: { label: 'Ready to Schedule', color: '#15803d', bg: '#f0fdf4', dot: '#22c55e' },
  scheduled:         { label: 'Scheduled',          color: '#a16207', bg: '#fefce8', dot: '#eab308' },
  completed:         { label: 'Completed',           color: '#1d4ed8', bg: '#eff6ff', dot: '#3b82f6' },
  dropped:           { label: 'Dropped',             color: '#dc2626', bg: '#fef2f2', dot: '#ef4444' },
  on_hold:           { label: 'On Hold',             color: '#6b7280', bg: '#f9fafb', dot: '#9ca3af' },
}

export default function StatusBadge({ status, size = 'md' }) {
  const cfg = STATUS_CONFIG[status] || STATUS_CONFIG.on_hold
  return (
    <span style={{ display:'inline-flex', alignItems:'center', gap:6, padding: size==='sm' ? '2px 8px':'4px 12px', borderRadius:20, fontSize: size==='sm'?10:11, fontWeight:700, textTransform:'uppercase', letterSpacing:'0.04em', background:cfg.bg, color:cfg.color }}>
      <span style={{ width:6, height:6, borderRadius:'50%', background:cfg.dot, flexShrink:0 }}></span>
      {cfg.label}
    </span>
  )
}

export { STATUS_CONFIG }
