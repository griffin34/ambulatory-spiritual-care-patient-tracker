// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

import React, { useState } from 'react'
import { format, parseISO, startOfMonth, endOfMonth } from 'date-fns'
import DateRangePicker from '../components/DateRangePicker'
import BarChart from '../components/BarChart'
import PrintButton from '../components/PrintButton'

const defaultRange = () => ({
  from: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
  to: format(endOfMonth(new Date()), 'yyyy-MM-dd')
})

// Report definitions, keyed for the selector dropdown. Each entry's shape
// matches what ResultCard needs to render a chart + table for that report.
const REPORTS = [
  {
    key: 'referralsBySource',
    title: 'Referrals by Source',
    desc: 'New referrals received, grouped by referral source',
    channel: 'reports:referralsBySource',
    renderChart: rows => <BarChart rows={rows} labelKey="source" valueKey="count" color="#6366f1" />,
    columns: [{key:'source',label:'Source'},{key:'count',label:'Count',align:'right'},{key:'pct',label:'%',align:'right'}],
    renderTable: rows => {
      const total = rows.reduce((s, r) => s + r.count, 0)
      return rows.map((r, i) => (
        <tr key={i}><td>{r.source || 'Unknown'}</td><td style={{textAlign:'right',fontWeight:700}}>{r.count}</td><td style={{textAlign:'right',color:'#718096'}}>{total ? Math.round(r.count/total*100) : 0}%</td></tr>
      ))
    }
  },
  {
    key: 'firstAppointments',
    title: 'First Appointments',
    desc: 'Patients whose first appointment occurred within the date range',
    channel: 'reports:firstAppointments',
    renderChart: rows => {
      const byWeek = rows.reduce((acc, r) => {
        const week = format(parseISO(r.first_appt_date), "'Wk of' MMM d")
        acc[week] = (acc[week] || 0) + 1
        return acc
      }, {})
      return <BarChart rows={Object.entries(byWeek).map(([source,count]) => ({source,count}))} labelKey="source" valueKey="count" color="#22c55e" />
    },
    columns: [{key:'name',label:'Patient'},{key:'first_appt_date',label:'First Appt'},{key:'consultant_name',label:'Consultant'}],
    renderTable: rows => rows.map((r, i) => (
      <tr key={i}><td>{r.last_name}, {r.first_name}</td><td style={{color:'#718096',fontSize:11}}>{r.first_appt_date}</td><td style={{color:'#718096'}}>{r.consultant_name || '—'}</td></tr>
    ))
  },
  {
    key: 'patientsDropped',
    title: 'Patients Dropped',
    desc: 'Patients whose status was changed to Dropped within the date range',
    channel: 'reports:patientsDropped',
    renderChart: rows => {
      const byWeek = rows.reduce((acc, r) => {
        const week = format(parseISO(r.changed_at.slice(0, 10)), "'Wk of' MMM d")
        acc[week] = (acc[week] || 0) + 1
        return acc
      }, {})
      return <BarChart rows={Object.entries(byWeek).map(([source,count]) => ({source,count}))} labelKey="source" valueKey="count" color="#ef4444" />
    },
    columns: [{key:'name',label:'Patient'},{key:'changed_at',label:'Dropped On'},{key:'changed_by_name',label:'Changed By'}],
    renderTable: rows => rows.map((r, i) => (
      <tr key={i}><td>{r.last_name}, {r.first_name}</td><td style={{color:'#718096',fontSize:11}}>{r.changed_at?.slice(0,10)}</td><td style={{color:'#718096'}}>{r.changed_by_name || '—'}</td></tr>
    ))
  },
  {
    key: 'sdatImprovement',
    title: 'SDAT Improvement',
    desc: 'Patients whose ending SDAT falls in the range — lower distress is better',
    channel: 'reports:sdatImprovement',
    renderChart: rows => <BarChart rows={rows.map(r => ({ source: `${r.last_name}, ${r.first_name}`, count: r.pct_improvement ?? 0 }))} labelKey="source" valueKey="count" color="#0ea5e9" />,
    columns: [{key:'patient',label:'Patient'},{key:'begin',label:'Begin',align:'right'},{key:'begin_date',label:'Begin Date'},{key:'end',label:'End',align:'right'},{key:'end_date',label:'End Date'},{key:'pct',label:'% Improvement',align:'right'}],
    renderTable: rows => {
      const A = rows.reduce((s, r) => s + (r.begin_score || 0), 0)
      const B = rows.reduce((s, r) => s + (r.end_score || 0), 0)
      const overall = A ? Math.round((A - B) / A * 1000) / 10 : 0
      return [
        ...rows.map((r, i) => (
          <tr key={i}>
            <td>{r.last_name}, {r.first_name}</td>
            <td style={{textAlign:'right'}}>{r.begin_score}</td>
            <td style={{color:'#718096',fontSize:11}}>{r.begin_date || '—'}</td>
            <td style={{textAlign:'right'}}>{r.end_score}</td>
            <td style={{color:'#718096',fontSize:11}}>{r.end_date || '—'}</td>
            <td style={{textAlign:'right',fontWeight:700}}>{r.pct_improvement == null ? 'N/A' : `${r.pct_improvement}%`}</td>
          </tr>
        )),
        <tr key="__total" style={{borderTop:'2px solid #e2e8f0',fontWeight:700}}>
          <td>Overall ({rows.length})</td>
          <td style={{textAlign:'right'}}>{A}</td>
          <td></td>
          <td style={{textAlign:'right'}}>{B}</td>
          <td></td>
          <td style={{textAlign:'right'}}>{overall}%</td>
        </tr>
      ]
    }
  },
]

function ResultCard({ report, results, range }) {
  const exportResults = async () => {
    const result = await window.ipc.invoke('dialog:showSaveDialog', { defaultPath: `${report.title.replace(/\s+/g,'-')}.xlsx`, filters: [{ name: 'Excel', extensions: ['xlsx'] }] })
    const filePath = result?.filePath
    if (filePath) await window.ipc.invoke('excel:exportReport', { filePath, rows: results, sheetName: report.title })
  }

  return (
    <div className="report-card">
      <div className="report-header">
        <div className="report-title-area">
          <div className="report-title">{report.title}</div>
          <div className="report-desc">{report.desc}</div>
          <div className="print-only print-range">Range: {format(parseISO(range.from), 'MM/dd/yyyy')} – {format(parseISO(range.to), 'MM/dd/yyyy')}</div>
        </div>
        {results.length > 0 && <button className="btn-export no-print" onClick={exportResults}>⬇ Export</button>}
      </div>
      {results.length === 0 ? (
        <div className="report-body">
          <div style={{textAlign:'center',padding:32,color:'#a0aec0'}}>No results found for this date range.</div>
        </div>
      ) : (
        <div className="report-body">
          <div className="chart-area">{report.renderChart(results)}</div>
          <div className="report-divider"></div>
          <div className="table-panel">
            <div className="table-panel-header">
              <span className="table-panel-title">All Results</span>
              <span className="table-row-count">{results.length} rows</span>
            </div>
            <div className="table-scroll">
              <table>
                <thead><tr>{report.columns.map(c => <th key={c.key} style={c.align==='right'?{textAlign:'right'}:{}}>{c.label}</th>)}</tr></thead>
                <tbody>{report.renderTable(results)}</tbody>
              </table>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default function Reports() {
  const [selected, setSelected] = useState('all')
  const [range, setRange] = useState(defaultRange())
  const [loading, setLoading] = useState(false)
  // Only ever holds the report(s) + range from the most recent Run click —
  // selecting a different report or range doesn't change what's shown until Run.
  const [run, setRun] = useState({ range: defaultRange(), resultsByKey: {} })

  const handleRun = async () => {
    setLoading(true)
    const toRun = selected === 'all' ? REPORTS : REPORTS.filter(r => r.key === selected)
    const entries = await Promise.all(toRun.map(async r => [r.key, await window.ipc.invoke(r.channel, range)]))
    setRun({ range, resultsByKey: Object.fromEntries(entries) })
    setLoading(false)
  }

  return (
    <div className="page">
      <div className="topbar">
        <h1>Reports</h1>
        <div className="topbar-right"><PrintButton /></div>
      </div>
      <div className="content">
        <div className="report-card no-print">
          <div className="report-header">
            <div className="report-controls">
              <select className="report-select" value={selected} onChange={e => setSelected(e.target.value)}>
                <option value="all">All Reports</option>
                {REPORTS.map(r => <option key={r.key} value={r.key}>{r.title}</option>)}
              </select>
              <DateRangePicker from={range.from} to={range.to} onChange={setRange} />
              <button className="btn-run" onClick={handleRun} disabled={loading}>{loading ? '…' : 'Run'}</button>
            </div>
          </div>
        </div>

        {REPORTS.filter(r => run.resultsByKey[r.key]).map(r => (
          <ResultCard key={r.key} report={r} results={run.resultsByKey[r.key]} range={run.range} />
        ))}
      </div>
    </div>
  )
}
