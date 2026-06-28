// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

import React, { useState, useEffect, useCallback, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import StatusBadge, { STATUS_CONFIG } from '../components/StatusBadge'
import PrintButton from '../components/PrintButton'
import { useAuth } from '../hooks/useAuth'
import { format, parseISO } from 'date-fns'

const STATUSES = ['ready_to_schedule','scheduled','completed','dropped','on_hold']

// Sortable columns: key + display label + value accessor for client-side sort.
const COLUMNS = [
  { key: 'name',             label: 'Patient Name',     accessor: p => `${p.last_name}, ${p.first_name}`.toLowerCase() },
  { key: 'mrn',              label: 'MRN',              accessor: p => p.mrn },
  { key: 'date_of_referral', label: 'Referral Date',    accessor: p => p.date_of_referral },
  { key: 'referral_source',  label: 'Referral Source',  accessor: p => p.referral_source },
  { key: 'language',         label: 'Language',         accessor: p => p.language },
  { key: 'next_appointment', label: 'Next Appointment', accessor: p => p.next_appointment },
  { key: 'current_status',   label: 'Status',           accessor: p => p.current_status },
]

export default function WorkQueue() {
  const [patients, setPatients] = useState([])
  const [filters, setFilters] = useState({ status: '', search: '' })
  const [loading, setLoading] = useState(true)
  const [sortKey, setSortKey] = useState(null)
  const [sortDir, setSortDir] = useState('asc')
  const navigate = useNavigate()
  const { user } = useAuth()

  const load = useCallback(async () => {
    setLoading(true)
    const list = await window.ipc.invoke('patients:list', filters)
    setPatients(list)
    setLoading(false)
  }, [filters])

  useEffect(() => { load() }, [load])

  const toggleSort = (key) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc')
    else { setSortKey(key); setSortDir('asc') }
  }

  const sorted = useMemo(() => {
    if (!sortKey) return patients
    const col = COLUMNS.find(c => c.key === sortKey)
    const dir = sortDir === 'desc' ? -1 : 1
    return [...patients].sort((a, b) => {
      const av = col.accessor(a), bv = col.accessor(b)
      if (av == null && bv == null) return 0
      if (av == null) return 1   // nulls always sort last
      if (bv == null) return -1
      if (av < bv) return -1 * dir
      if (av > bv) return 1 * dir
      return 0
    })
  }, [patients, sortKey, sortDir])

  const viewingDeleted = filters.status === 'deleted'

  const handleRestore = async (p) => {
    await window.ipc.invoke('patients:restore', { patientId: p.id, userId: user?.id ?? null })
    load()
  }

  const counts = STATUSES.reduce((acc, s) => ({ ...acc, [s]: patients.filter(p => p.current_status === s).length }), {})

  const handleImport = async () => {
    const { filePaths } = await window.ipc.invoke('dialog:showOpenDialog', { filters: [{ name: 'Excel', extensions: ['xlsx','xls'] }], properties: ['openFile'] })
    if (!filePaths?.length) return
    const { rows, columns } = await window.ipc.invoke('excel:parseImportFile', { filePath: filePaths[0] })
    const confirmed = confirm(`Found ${rows.length} rows with columns: ${columns.join(', ')}.\n\nImport with auto-mapping (last_name, first_name, mrn, phone, date_of_referral)?`)
    if (!confirmed) return
    const columnMap = { last_name: 'last_name', first_name: 'first_name', mrn: 'mrn', phone: 'phone', date_of_referral: 'date_of_referral' }
    const result = await window.ipc.invoke('excel:importPatients', { rows, columnMap, userId: null })
    alert(`Imported ${result.imported} patients successfully.`)
    load()
  }

  return (
    <div className="page">
      <div className="topbar">
        <h1>Work Queue</h1>
        <div className="topbar-right">
          <input className="search-input" placeholder="Search by name or MRN…" value={filters.search} onChange={e => setFilters(f => ({...f, search: e.target.value}))} />
          <PrintButton />
          <button className="btn btn-outline" onClick={handleImport}>Import Excel</button>
          <button className="btn btn-primary" onClick={() => navigate('/queue/new')}>+ Add Patient</button>
        </div>
      </div>

      <div className="stats-bar">
        <div className="stat"><span className="stat-value">{patients.length}</span><span className="stat-label">Total Active</span></div>
        {STATUSES.map(s => (
          <div key={s} className="stat">
            <span className="stat-value" style={{ color: STATUS_CONFIG[s].dot }}>{counts[s]}</span>
            <span className="stat-label">{STATUS_CONFIG[s].label}</span>
          </div>
        ))}
      </div>

      <div className="filters">
        <span className="filter-label">Status</span>
        <button className={`filter-chip${!filters.status?' active':''}`} onClick={() => setFilters(f => ({...f, status:''}))}>All</button>
        {STATUSES.map(s => (
          <button key={s} className={`filter-chip${filters.status===s?' active':''}`} onClick={() => setFilters(f => ({...f, status: f.status===s?'':s}))} style={filters.status===s?{}:{borderColor: STATUS_CONFIG[s].dot+'66', color: STATUS_CONFIG[s].color}}>
            {STATUS_CONFIG[s].label}
          </button>
        ))}
        <button className={`filter-chip${viewingDeleted?' active':''}`} onClick={() => setFilters(f => ({...f, status: f.status==='deleted'?'':'deleted'}))} style={viewingDeleted?{}:{borderColor: STATUS_CONFIG.deleted.dot+'66', color: STATUS_CONFIG.deleted.color}}>
          {STATUS_CONFIG.deleted.label}
        </button>
      </div>

      <div className="table-area">
        <table>
          <thead><tr>
            {COLUMNS.map(c => (
              <th key={c.key} onClick={() => toggleSort(c.key)} style={{cursor:'pointer', userSelect:'none'}}>
                {c.label}{sortKey === c.key ? (sortDir === 'asc' ? ' ▲' : ' ▼') : ''}
              </th>
            ))}
            <th className="no-print"></th>
          </tr></thead>
          <tbody>
            {loading ? <tr><td colSpan={8} style={{textAlign:'center',padding:32,color:'#a0aec0'}}>Loading…</td></tr>
            : sorted.length === 0 ? <tr><td colSpan={8} style={{textAlign:'center',padding:32,color:'#a0aec0'}}>No patients found</td></tr>
            : sorted.map(p => (
              <tr key={p.id} onClick={() => navigate(`/queue/${p.id}`)} style={{cursor:'pointer'}}>
                <td className="name">{p.last_name}, {p.first_name}{p.middle_name ? ` ${p.middle_name[0]}.`:''}</td>
                <td className="mrn">{p.mrn || '—'}</td>
                <td className="date">{p.date_of_referral ? format(parseISO(p.date_of_referral), 'MM/dd/yyyy') : '—'}</td>
                <td>{p.referral_source || '—'}</td>
                <td>{p.language || '—'}</td>
                <td>{p.next_appointment ? format(parseISO(p.next_appointment.replace(' ', 'T')), 'MMM d, h:mm a') : <span style={{color:'#a0aec0',fontStyle:'italic'}}>None</span>}</td>
                <td><StatusBadge status={p.current_status} /></td>
                <td className="no-print">
                  {viewingDeleted
                    ? <button className="action-btn" onClick={e => {e.stopPropagation(); handleRestore(p)}}>Restore</button>
                    : <button className="action-btn" onClick={e => {e.stopPropagation(); navigate(`/queue/${p.id}`)}}>View</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
