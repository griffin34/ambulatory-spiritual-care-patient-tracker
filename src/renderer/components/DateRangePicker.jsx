import React from 'react'

export default function DateRangePicker({ from, to, onChange }) {
  return (
    <div className="date-range-picker">
      <input type="date" value={from} onChange={e => onChange({ from: e.target.value, to })} className="date-input" />
      <span className="date-sep">→</span>
      <input type="date" value={to} onChange={e => onChange({ from, to: e.target.value })} className="date-input" />
    </div>
  )
}
