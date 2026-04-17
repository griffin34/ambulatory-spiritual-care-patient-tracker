// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

import React, { useState, useEffect } from 'react'

const LOV_CATEGORIES = [
  { key: 'referral_source', label: 'Referral Sources' },
  { key: 'religion', label: 'Religions' },
  { key: 'language', label: 'Languages' },
  { key: 'appointment_type', label: 'Appt Types' },
]

export default function Admin() {
  const [users, setUsers] = useState([])
  const [lovCategory, setLovCategory] = useState('referral_source')
  const [lovs, setLovs] = useState([])
  const [consultants, setConsultants] = useState([])
  const [newUserForm, setNewUserForm] = useState(null)
  const [newLovValue, setNewLovValue] = useState('')
  const [newConsultant, setNewConsultant] = useState({ name: '', is_chaplain: false })
  const [importState, setImportState] = useState('idle') // 'idle' | 'preview' | 'importing' | 'done'
  const [importPreview, setImportPreview] = useState(null) // { rows, patientCount, apptCount }
  const [importResult, setImportResult] = useState(null)  // { patients_imported, patients_skipped, appointments_imported }

  const loadUsers = () => window.ipc.invoke('admin:listUsers').then(setUsers)
  const loadLovs = (cat) => window.ipc.invoke('admin:listLovs', { category: cat }).then(setLovs)
  const loadConsultants = () => window.ipc.invoke('admin:listConsultants').then(setConsultants)

  useEffect(() => { loadUsers(); loadConsultants() }, [])
  useEffect(() => { loadLovs(lovCategory) }, [lovCategory])

  const handleCreateUser = async (e) => {
    e.preventDefault()
    await window.ipc.invoke('admin:createUser', newUserForm)
    setNewUserForm(null)
    loadUsers()
  }

  const handleAddLov = async (e) => {
    e.preventDefault()
    if (!newLovValue.trim()) return
    await window.ipc.invoke('admin:upsertLov', { category: lovCategory, value: newLovValue.trim(), sort_order: lovs.length + 1 })
    setNewLovValue('')
    loadLovs(lovCategory)
  }

  const handleAddConsultant = async (e) => {
    e.preventDefault()
    if (!newConsultant.name.trim()) return
    await window.ipc.invoke('admin:upsertConsultant', { name: newConsultant.name.trim(), is_chaplain: newConsultant.is_chaplain })
    setNewConsultant({ name: '', is_chaplain: false })
    loadConsultants()
  }

  const handlePickImportFile = async () => {
    const { canceled, filePaths } = await window.ipc.invoke('dialog:showOpenDialog', {
      title: 'Select Historical Import File',
      filters: [{ name: 'Excel Files', extensions: ['xlsx'] }],
      properties: ['openFile'],
    })
    if (canceled || !filePaths.length) return

    const { rows } = await window.ipc.invoke('excel:parseImportFile', { filePath: filePaths[0] })

    // Detect patient groups for preview count
    const seen = new Set()
    let patientCount = 0
    let apptCount = 0
    for (const row of rows) {
      const last = String(row.last_name || '').trim()
      const first = String(row.first_name || '').trim()
      if (!last || !first) continue
      const mrn = String(row.mrn || '').trim()
      const key = mrn ? `mrn::${mrn}` : `name::${last.toLowerCase()}::${first.toLowerCase()}`
      if (!seen.has(key)) { seen.add(key); patientCount++ }
      if (String(row.appt_date || '').trim()) apptCount++
    }

    setImportPreview({ rows, patientCount, apptCount })
    setImportState('preview')
  }

  const handleConfirmImport = async () => {
    if (!importPreview) return
    setImportState('importing')
    const result = await window.ipc.invoke('excel:importHistorical', { rows: importPreview.rows })
    setImportResult(result)
    setImportState('done')
  }

  const handleDownloadTemplate = async () => {
    const { canceled, filePath } = await window.ipc.invoke('dialog:showSaveDialog', {
      title: 'Save Import Template',
      defaultPath: 'patient_import_template.xlsx',
      filters: [{ name: 'Excel Files', extensions: ['xlsx'] }],
    })
    if (canceled || !filePath) return
    await window.ipc.invoke('excel:generateImportTemplate', { filePath })
  }

  const handleResetImport = () => {
    setImportState('idle')
    setImportPreview(null)
    setImportResult(null)
  }

  const initials = (name) => name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase()
  const ROLE_COLORS = { admin: { bg:'#ede9fe', color:'#6d28d9' }, coordinator: { bg:'#f0fdf4', color:'#15803d' } }

  return (
    <div className="page">
      <div className="topbar"><h1>Admin</h1></div>
      <div className="content admin-layout">

        <div className="panel">
          <div className="panel-header">
            <div><h2>User Management</h2><div className="sub">{users.length} users · {users.filter(u=>u.is_active).length} active</div></div>
            <button className="btn btn-primary" onClick={() => setNewUserForm({ name:'', email:'', password:'', role:'coordinator' })}>+ Add User</button>
          </div>

          {newUserForm && (
            <form className="inline-form" onSubmit={handleCreateUser}>
              {[['name','Name'],['email','User ID'],['password','Password']].map(([f,l]) => (
                <div key={f} className="field"><label>{l}</label><input type={f==='password'?'password':'text'} value={newUserForm[f]} onChange={e => setNewUserForm(v => ({...v,[f]:e.target.value}))} required /></div>
              ))}
              <div className="field"><label>Role</label><select value={newUserForm.role} onChange={e => setNewUserForm(v => ({...v, role:e.target.value}))}><option value="coordinator">Coordinator</option><option value="admin">Admin</option></select></div>
              <div className="form-actions"><button type="button" className="btn btn-outline" onClick={() => setNewUserForm(null)}>Cancel</button><button type="submit" className="btn btn-primary">Create</button></div>
            </form>
          )}

          <div className="panel-body">
            {users.map(u => (
              <div key={u.id} className={`user-row${!u.is_active?' inactive':''}`}>
                <div className="user-avatar" style={{ background: u.is_active ? '#6366f1' : '#9ca3af' }}>{initials(u.name)}</div>
                <div className="user-info-col"><div className="user-display-name">{u.name}</div><div className="user-email">{u.email}</div></div> {/* u.email is the User ID */}
                <span className="role-badge" style={ROLE_COLORS[u.role]}>{u.role}</span>
                <div className={`status-dot status-${u.is_active?'active':'inactive'}`}></div>
                <div className="user-actions">
                  <button className="btn-sm" onClick={async () => { const pw = prompt('New password:'); if (pw) { await window.ipc.invoke('admin:resetPassword', { id: u.id, newPassword: pw }) } }}>Reset PW</button>
                  <button className={`btn-sm${u.is_active?' btn-danger':''}`} onClick={async () => { await window.ipc.invoke('admin:setUserActive', { id: u.id, is_active: u.is_active ? 0 : 1 }); loadUsers() }}>
                    {u.is_active ? 'Deactivate' : 'Activate'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="panel">
          <div className="panel-header"><h2>List of Values</h2></div>
          <div className="lov-tabs">
            {LOV_CATEGORIES.map(c => <button key={c.key} className={`lov-tab${lovCategory===c.key?' active':''}`} onClick={() => setLovCategory(c.key)}>{c.label}</button>)}
            <button className={`lov-tab${lovCategory==='consultant'?' active':''}`} onClick={() => setLovCategory('consultant')}>Consultants</button>
          </div>

          {lovCategory === 'consultant' ? (
            <div className="lov-body">
              <form className="lov-toolbar consultant-toolbar" onSubmit={handleAddConsultant}>
                <input className="lov-input" placeholder="Add consultant name…" value={newConsultant.name} onChange={e => setNewConsultant(v => ({...v, name: e.target.value}))} />
                <label className="chaplain-check">
                  <input type="checkbox" checked={newConsultant.is_chaplain} onChange={e => setNewConsultant(v => ({...v, is_chaplain: e.target.checked}))} />
                  Chaplain
                </label>
                <button type="submit" className="btn-add">+ Add</button>
              </form>
              <div className="lov-list">
                {consultants.map(c => (
                  <div key={c.id} className="lov-item">
                    <span className={`lov-value${!c.is_active?' lov-inactive':''}`}>{c.name}</span>
                    {!!c.is_chaplain && <span className="chaplain-badge">Chaplain</span>}
                    <div className="lov-actions">
                      <button className="icon-btn" onClick={async () => { await window.ipc.invoke('admin:setConsultantActive', { id: c.id, is_active: c.is_active ? 0 : 1 }); loadConsultants() }}>{c.is_active ? '🗑' : '↩'}</button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div className="lov-body">
              <form className="lov-toolbar" onSubmit={handleAddLov}>
                <input className="lov-input" placeholder={`Add value…`} value={newLovValue} onChange={e => setNewLovValue(e.target.value)} />
                <button type="submit" className="btn-add">+ Add</button>
              </form>
              <div className="lov-list">
                {lovs.map(l => (
                  <div key={l.id} className="lov-item">
                    <span className="lov-value">{l.value}</span>
                    <div className="lov-actions">
                      <button className="icon-btn danger" onClick={async () => { await window.ipc.invoke('admin:deleteLov', { id: l.id }); loadLovs(lovCategory) }}>🗑</button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="panel">
          <div className="panel-header">
            <div>
              <h2>Import Historical Data</h2>
              <div className="sub">Load patients and appointments from the standard import template</div>
            </div>
            <button className="btn btn-outline" onClick={handleDownloadTemplate}>Download Template</button>
          </div>

          {importState === 'idle' && (
            <div className="panel-body import-idle">
              <p className="import-hint">Select a filled-in template file to preview before importing.</p>
              <button className="btn btn-primary" onClick={handlePickImportFile}>Select File…</button>
            </div>
          )}

          {importState === 'preview' && importPreview && (
            <div className="panel-body import-preview">
              <div className="import-counts">
                <div className="import-count-item"><span className="import-count-num">{importPreview.patientCount}</span><span className="import-count-label">patients detected</span></div>
                <div className="import-count-item"><span className="import-count-num">{importPreview.apptCount}</span><span className="import-count-label">appointments detected</span></div>
              </div>
              <p className="import-hint">Patients whose MRN already exists in the database will be skipped.</p>
              <div className="form-actions">
                <button className="btn btn-outline" onClick={handleResetImport}>Cancel</button>
                <button className="btn btn-primary" onClick={handleConfirmImport}>Import</button>
              </div>
            </div>
          )}

          {importState === 'importing' && (
            <div className="panel-body import-idle"><p className="import-hint">Importing…</p></div>
          )}

          {importState === 'done' && importResult && (
            <div className="panel-body import-done">
              <div className="import-counts">
                <div className="import-count-item"><span className="import-count-num">{importResult.patients_imported}</span><span className="import-count-label">patients imported</span></div>
                <div className="import-count-item"><span className="import-count-num">{importResult.patients_skipped}</span><span className="import-count-label">patients skipped</span></div>
                <div className="import-count-item"><span className="import-count-num">{importResult.appointments_imported}</span><span className="import-count-label">appointments imported</span></div>
              </div>
              <button className="btn btn-outline" onClick={handleResetImport}>Import Another File</button>
            </div>
          )}
        </div>

      </div>
    </div>
  )
}
