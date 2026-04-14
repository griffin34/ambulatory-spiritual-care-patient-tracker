import React, { useState } from 'react'
import { format, startOfMonth, endOfMonth, subMonths } from 'date-fns'
import DateRangePicker from '../components/DateRangePicker'
import BarChart from '../components/BarChart'

const defaultRange = () => ({
  from: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
  to: format(endOfMonth(new Date()), 'yyyy-MM-dd')
})

function ReportCard({ title, desc, channel, renderChart, renderTable, columns }) {
  const [range, setRange] = useState(defaultRange())
  const [results, setResults] = useState(null)
  const [loading, setLoading] = useState(false)

  const run = async () => {
    setLoading(true)
    const data = await window.ipc.invoke(channel, range)
    setResults(data)
    setLoading(false)
  }

  const exportResults = async () => {
    const result = await window.ipc.invoke('dialog:showSaveDialog', { defaultPath: `${title.replace(/\s+/g,'-')}.xlsx`, filters: [{ name: 'Excel', extensions: ['xlsx'] }] })
    const filePath = result?.filePath
    if (filePath) await window.ipc.invoke('excel:exportReport', { filePath, rows: results, sheetName: title })
  }

  return (
    <div className="report-card">
      <div className="report-header">
        <div className="report-title-area">
          <div className="report-title">{title}</div>
          <div className="report-desc">{desc}</div>
        </div>
        <div className="report-controls">
          <DateRangePicker from={range.from} to={range.to} onChange={setRange} />
          <button className="btn-run" onClick={run} disabled={loading}>{loading ? '…' : 'Run'}</button>
          {results && <button className="btn-export" onClick={exportResults}>⬇ Export</button>}
        </div>
      </div>
      {results && (
        <div className="report-body">
          <div className="chart-area">{renderChart(results)}</div>
          <div className="report-divider"></div>
          <div className="table-panel">
            <div className="table-panel-header">
              <span className="table-panel-title">All Results</span>
              <span className="table-row-count">{results.length} rows</span>
            </div>
            <div className="table-scroll">
              <table>
                <thead><tr>{columns.map(c => <th key={c.key} style={c.align==='right'?{textAlign:'right'}:{}}>{c.label}</th>)}</tr></thead>
                <tbody>{renderTable(results)}</tbody>
              </table>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default function Reports() {
  return (
    <div className="page">
      <div className="topbar"><h1>Reports</h1></div>
      <div className="content">
        <ReportCard
          title="Referrals by Source"
          desc="New referrals received, grouped by referral source"
          channel="reports:referralsBySource"
          renderChart={rows => <BarChart rows={rows} labelKey="source" valueKey="count" color="#6366f1" />}
          columns={[{key:'source',label:'Source'},{key:'count',label:'Count',align:'right'},{key:'pct',label:'%',align:'right'}]}
          renderTable={rows => {
            const total = rows.reduce((s, r) => s + r.count, 0)
            return rows.map((r, i) => (
              <tr key={i}><td>{r.source || 'Unknown'}</td><td style={{textAlign:'right',fontWeight:700}}>{r.count}</td><td style={{textAlign:'right',color:'#718096'}}>{total ? Math.round(r.count/total*100) : 0}%</td></tr>
            ))
          }}
        />
        <ReportCard
          title="First Appointments"
          desc="Patients whose first appointment occurred within the date range"
          channel="reports:firstAppointments"
          renderChart={rows => {
            const byWeek = rows.reduce((acc, r) => {
              const week = format(new Date(r.first_appt_date), "'Wk of' MMM d")
              acc[week] = (acc[week] || 0) + 1
              return acc
            }, {})
            return <BarChart rows={Object.entries(byWeek).map(([source,count]) => ({source,count}))} labelKey="source" valueKey="count" color="#22c55e" />
          }}
          columns={[{key:'name',label:'Patient'},{key:'first_appt_date',label:'First Appt'},{key:'consultant_name',label:'Consultant'}]}
          renderTable={rows => rows.map((r, i) => (
            <tr key={i}><td>{r.last_name}, {r.first_name}</td><td style={{color:'#718096',fontSize:11}}>{r.first_appt_date}</td><td style={{color:'#718096'}}>{r.consultant_name || '—'}</td></tr>
          ))}
        />
        <ReportCard
          title="Patients Dropped"
          desc="Patients whose status was changed to Dropped within the date range"
          channel="reports:patientsDropped"
          renderChart={rows => {
            const byWeek = rows.reduce((acc, r) => {
              const week = format(new Date(r.changed_at), "'Wk of' MMM d")
              acc[week] = (acc[week] || 0) + 1
              return acc
            }, {})
            return <BarChart rows={Object.entries(byWeek).map(([source,count]) => ({source,count}))} labelKey="source" valueKey="count" color="#ef4444" />
          }}
          columns={[{key:'name',label:'Patient'},{key:'changed_at',label:'Dropped On'},{key:'changed_by_name',label:'Changed By'}]}
          renderTable={rows => rows.map((r, i) => (
            <tr key={i}><td>{r.last_name}, {r.first_name}</td><td style={{color:'#718096',fontSize:11}}>{r.changed_at?.slice(0,10)}</td><td style={{color:'#718096'}}>{r.changed_by_name || '—'}</td></tr>
          ))}
        />
      </div>
    </div>
  )
}
