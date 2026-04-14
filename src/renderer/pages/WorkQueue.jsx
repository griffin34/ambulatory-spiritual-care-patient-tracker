import React, { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import StatusBadge, { STATUS_CONFIG } from '../components/StatusBadge'
import { useAuth } from '../hooks/useAuth'
import { format, parseISO } from 'date-fns'

const STATUSES = ['ready_to_schedule','scheduled','completed','dropped','on_hold']

export default function WorkQueue() {
  const [patients, setPatients] = useState([])
  const [filters, setFilters] = useState({ status: '', search: '' })
  const [loading, setLoading] = useState(true)
  const navigate = useNavigate()
  const { token } = useAuth()

  const load = useCallback(async () => {
    setLoading(true)
    const list = await window.ipc.invoke('patients:list', filters)
    setPatients(list)
    setLoading(false)
  }, [filters])

  useEffect(() => { load() }, [load])

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
      </div>

      <div className="table-area">
        <table>
          <thead><tr>
            <th>Patient Name</th><th>MRN</th><th>Referral Date</th>
            <th>Referral Source</th><th>Language</th><th>Next Appointment</th><th>Status</th><th></th>
          </tr></thead>
          <tbody>
            {loading ? <tr><td colSpan={8} style={{textAlign:'center',padding:32,color:'#a0aec0'}}>Loading…</td></tr>
            : patients.length === 0 ? <tr><td colSpan={8} style={{textAlign:'center',padding:32,color:'#a0aec0'}}>No patients found</td></tr>
            : patients.map(p => (
              <tr key={p.id} onClick={() => navigate(`/queue/${p.id}`)} style={{cursor:'pointer'}}>
                <td className="name">{p.last_name}, {p.first_name}{p.middle_name ? ` ${p.middle_name[0]}.`:''}</td>
                <td className="mrn">{p.mrn || '—'}</td>
                <td className="date">{p.date_of_referral ? format(parseISO(p.date_of_referral), 'MM/dd/yyyy') : '—'}</td>
                <td>{p.referral_source || '—'}</td>
                <td>{p.language || '—'}</td>
                <td>{p.next_appointment ? format(parseISO(p.next_appointment.replace(' ', 'T')), 'MMM d, h:mm a') : <span style={{color:'#a0aec0',fontStyle:'italic'}}>None</span>}</td>
                <td><StatusBadge status={p.current_status} /></td>
                <td><button className="action-btn" onClick={e => {e.stopPropagation(); navigate(`/queue/${p.id}`)}}>View</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
