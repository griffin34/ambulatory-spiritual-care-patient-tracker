import React, { useState, useEffect } from 'react'
import { format, addDays, subDays, parseISO } from 'date-fns'

const APPT_STATUS = {
  scheduled: { bg: '#fefce8', border: '#eab308', label: 'Scheduled' },
  completed: { bg: '#eff6ff', border: '#3b82f6', label: 'Completed' },
  no_show:   { bg: '#fff7ed', border: '#f97316', label: 'No Show' },
  cancelled: { bg: '#fef2f2', border: '#ef4444', label: 'Cancelled' },
}

export default function Appointments() {
  const [date, setDate] = useState(format(new Date(), 'yyyy-MM-dd'))
  const [appointments, setAppointments] = useState([])
  const [daysWithAppts, setDaysWithAppts] = useState([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    const from = format(subDays(new Date(date), 14), 'yyyy-MM-dd')
    const to = format(addDays(new Date(date), 14), 'yyyy-MM-dd')
    window.ipc.invoke('appointments:daysWithAppointments', { from, to }).then(setDaysWithAppts)
  }, [date])

  useEffect(() => {
    setLoading(true)
    window.ipc.invoke('appointments:forDay', { date }).then(list => {
      setAppointments(list)
      setLoading(false)
    })
  }, [date])

  const stripDays = Array.from({ length: 16 }, (_, i) => {
    const d = format(addDays(subDays(new Date(date), 7), i), 'yyyy-MM-dd')
    return { date: d, hasAppts: daysWithAppts.includes(d), isToday: d === format(new Date(), 'yyyy-MM-dd'), isCurrent: d === date }
  })

  const grouped = appointments.reduce((acc, a) => {
    const key = a.time
    if (!acc[key]) acc[key] = []
    acc[key].push(a)
    return acc
  }, {})
  const times = Object.keys(grouped).sort()

  const counts = ['scheduled','completed','no_show','cancelled'].map(s => ({ status: s, count: appointments.filter(a => a.status === s).length }))

  return (
    <div className="page">
      <div className="topbar">
        <h1>Appointments</h1>
        <div className="topbar-right">
          <button className="btn btn-outline">Export</button>
        </div>
      </div>

      <div className="date-nav">
        <div className="date-nav-arrows">
          <button className="arrow-btn" onClick={() => setDate(format(subDays(new Date(date), 1), 'yyyy-MM-dd'))}>‹</button>
          <button className="arrow-btn" onClick={() => setDate(format(addDays(new Date(date), 1), 'yyyy-MM-dd'))}>›</button>
        </div>
        <div>
          <div className="current-date">{format(parseISO(date), 'EEEE, MMMM d, yyyy')}</div>
          <div className="date-subtitle">{appointments.length} appointment{appointments.length !== 1 ? 's' : ''}</div>
        </div>
        <div className="quick-jumps">
          <button className="jump-btn" onClick={() => setDate(format(subDays(new Date(), 14), 'yyyy-MM-dd'))}>-14 Days</button>
          <button className="jump-btn today" onClick={() => setDate(format(new Date(), 'yyyy-MM-dd'))}>Today</button>
        </div>
      </div>

      <div className="date-strip">
        {stripDays.map(d => (
          <div key={d.date} className={`strip-day${d.isCurrent?' today':''}${d.date < format(new Date(),'yyyy-MM-dd')?' past':''}`} onClick={() => setDate(d.date)}>
            <span className="dow">{format(parseISO(d.date), 'EEE').toUpperCase()}</span>
            <span className="dom">{format(parseISO(d.date), 'd')}</span>
            {d.hasAppts && <div className="appt-dot"></div>}
          </div>
        ))}
      </div>

      <div className="content">
        <div className="day-summary">
          {counts.map(({ status, count }) => (
            <div key={status} className="summary-chip">
              <div className="dot" style={{ background: APPT_STATUS[status].border }}></div>
              <span className="count">{count}</span>
              <span className="label">{APPT_STATUS[status].label}</span>
            </div>
          ))}
        </div>

        {loading ? <div style={{textAlign:'center',padding:32,color:'#a0aec0'}}>Loading…</div>
        : times.length === 0 ? <div style={{textAlign:'center',padding:48,color:'#a0aec0'}}>No appointments for this day</div>
        : times.map(time => (
          <div key={time} className="appt-row">
            <div className="appt-row-time"><span>{format(new Date(`2000-01-01T${time}`), 'h:mm a')}</span></div>
            <div className="appt-cards">
              {grouped[time].map(a => (
                <div key={a.id} className="appt-card" style={{ borderLeftColor: APPT_STATUS[a.status].border, background: APPT_STATUS[a.status].bg }}>
                  <div className="ac-name">{a.last_name}, {a.first_name}</div>
                  <div className="ac-consultant">{a.consultant_name || 'Unassigned'}</div>
                  <div className="ac-tags">
                    {a.type_label && <span className="ac-tag">{a.type_label}</span>}
                    {a.is_last_appointment ? <span className="ac-tag last">★ Last</span> : null}
                    <span className="ac-tag">{APPT_STATUS[a.status].label}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
