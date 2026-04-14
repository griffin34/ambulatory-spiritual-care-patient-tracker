import React, { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import StatusBadge, { STATUS_CONFIG } from '../components/StatusBadge'
import { useAuth } from '../hooks/useAuth'
import { format } from 'date-fns'

const STATUSES = ['ready_to_schedule','scheduled','completed','dropped','on_hold']

export default function PatientDetail() {
  const { id } = useParams()
  const isNew = id === 'new'
  const [patient, setPatient] = useState(null)
  const [editingProfile, setEditingProfile] = useState(isNew)
  const [showStatusMenu, setShowStatusMenu] = useState(false)
  const [showApptForm, setShowApptForm] = useState(false)
  const [lovs, setLovs] = useState({ referral_sources: [], religions: [], languages: [] })
  const [consultants, setConsultants] = useState([])
  const [apptTypes, setApptTypes] = useState([])
  const navigate = useNavigate()
  const { token } = useAuth()

  useEffect(() => {
    Promise.all([
      window.ipc.invoke('admin:listLovs', { category: 'referral_source' }),
      window.ipc.invoke('admin:listLovs', { category: 'religion' }),
      window.ipc.invoke('admin:listLovs', { category: 'language' }),
      window.ipc.invoke('admin:listConsultants'),
      window.ipc.invoke('admin:listLovs', { category: 'appointment_type' }),
    ]).then(([rs, rel, lang, cons, types]) => {
      setLovs({ referral_sources: rs, religions: rel, languages: lang })
      setConsultants(cons)
      setApptTypes(types)
    })
    if (!isNew) {
      window.ipc.invoke('patients:get', { id: Number(id) }).then(setPatient)
    }
  }, [id])

  const handleTransition = async (status) => {
    await window.ipc.invoke('patients:transitionStatus', { patientId: patient.id, status, userId: null })
    const updated = await window.ipc.invoke('patients:get', { id: patient.id })
    setPatient(updated)
    setShowStatusMenu(false)
  }

  const handleSaveProfile = async (form) => {
    if (isNew) {
      const p = await window.ipc.invoke('patients:create', { ...form, userId: null })
      navigate(`/queue/${p.id}`, { replace: true })
    } else {
      await window.ipc.invoke('patients:update', { id: patient.id, ...form })
      const updated = await window.ipc.invoke('patients:get', { id: patient.id })
      setPatient(updated)
      setEditingProfile(false)
    }
  }

  const handleSaveAppt = async (form) => {
    await window.ipc.invoke('appointments:create', { patient_id: patient.id, ...form })
    const updated = await window.ipc.invoke('patients:get', { id: patient.id })
    setPatient(updated)
    setShowApptForm(false)
  }

  if (!isNew && !patient) return <div className="loading-screen">Loading…</div>

  return (
    <div className="page">
      <div className="topbar">
        <div className="breadcrumb"><Link to="/queue">Work Queue</Link> › {isNew ? 'New Patient' : `${patient.last_name}, ${patient.first_name}`}</div>
        <div className="topbar-right">
          {!isNew && <button className="btn btn-outline" onClick={() => setEditingProfile(true)}>Edit Profile</button>}
          {!isNew && <button className="btn btn-primary" onClick={() => setShowApptForm(true)}>+ Add Appointment</button>}
        </div>
      </div>

      <div className="detail-layout">
        <div className="detail-left">
          {!isNew && (
            <div className="patient-header-card">
              <div className="patient-avatar">{patient.last_name[0]}{patient.first_name[0]}</div>
              <div>
                <div className="patient-name">{patient.last_name}, {patient.first_name} {patient.middle_name || ''}</div>
                <div className="patient-mrn">{patient.mrn || 'No MRN'}</div>
              </div>
              <div className="patient-header-right">
                <StatusBadge status={patient.current_status} />
                <div style={{ position:'relative' }}>
                  <button className="transition-btn" onClick={() => setShowStatusMenu(s => !s)}>Change Status ▾</button>
                  {showStatusMenu && (
                    <div className="status-menu">
                      {STATUSES.filter(s => s !== patient.current_status).map(s => (
                        <button key={s} className="status-menu-item" onClick={() => handleTransition(s)}>
                          <StatusBadge status={s} size="sm" />
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          <ProfileCard patient={patient} editing={editingProfile} lovs={lovs} onSave={handleSaveProfile} onCancel={() => { setEditingProfile(false); if (isNew) navigate('/queue') }} />

          {!isNew && patient.statusHistory?.length > 0 && (
            <div className="card">
              <div className="card-header"><h3>Status History</h3></div>
              <div className="card-body">
                {patient.statusHistory.map((h, i) => (
                  <div key={h.id} className="timeline-item">
                    <div className="tl-dot" style={{ background: STATUS_CONFIG[h.status]?.bg, color: STATUS_CONFIG[h.status]?.dot }}>●</div>
                    <div>
                      <div className="tl-status">{STATUS_CONFIG[h.status]?.label || h.status}</div>
                      <div className="tl-meta">{format(new Date(h.changed_at), 'MMM d, yyyy')} · {h.changed_by_name || 'System'}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {!isNew && (
          <div className="detail-right">
            <div className="card">
              <div className="card-header"><h3>Appointments</h3></div>
              <div className="card-body">
                {patient.appointments?.map(a => (
                  <AppointmentCard key={a.id} appt={a} onUpdate={async (fields) => {
                    await window.ipc.invoke('appointments:update', { id: a.id, ...fields })
                    const updated = await window.ipc.invoke('patients:get', { id: patient.id })
                    setPatient(updated)
                  }} />
                ))}
                {showApptForm && <AppointmentForm consultants={consultants} types={apptTypes} onSave={handleSaveAppt} onCancel={() => setShowApptForm(false)} />}
                {!showApptForm && <button className="add-appt-btn" onClick={() => setShowApptForm(true)}>+ Add Appointment</button>}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function ProfileCard({ patient, editing, lovs, onSave, onCancel }) {
  const [form, setForm] = useState({
    last_name: patient?.last_name || '', first_name: patient?.first_name || '',
    middle_name: patient?.middle_name || '', mrn: patient?.mrn || '',
    phone: patient?.phone || '', date_of_referral: patient?.date_of_referral || '',
    referral_source_id: patient?.referral_source_id || '', religion_id: patient?.religion_id || '',
    language_id: patient?.language_id || ''
  })

  if (!editing && patient) {
    return (
      <div className="card">
        <div className="card-header"><h3>Profile</h3></div>
        <div className="card-body">
          {[['Phone', patient.phone],['Referral Date', patient.date_of_referral],['Referral Source', patient.referral_source],['Religion', patient.religion],['Language', patient.language]].map(([label, value]) => (
            <div key={label} className="field-row">
              <span className="field-label">{label}</span>
              <span className="field-value">{value || '—'}</span>
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="card">
      <div className="card-header"><h3>{patient ? 'Edit Profile' : 'New Patient'}</h3></div>
      <div className="card-body">
        <form onSubmit={e => { e.preventDefault(); onSave(form) }}>
          {[['last_name','Last Name',true],['first_name','First Name',true],['middle_name','Middle Name',false],['mrn','MRN',false],['phone','Phone',false],['date_of_referral','Referral Date',false]].map(([field, label, req]) => (
            <div key={field} className="field">
              <label>{label}{req && ' *'}</label>
              <input type={field === 'date_of_referral' ? 'date' : 'text'} value={form[field]} onChange={e => setForm(f => ({...f, [field]: e.target.value}))} required={req} />
            </div>
          ))}
          {[['referral_source_id','Referral Source', lovs.referral_sources],['religion_id','Religion', lovs.religions],['language_id','Language', lovs.languages]].map(([field, label, options]) => (
            <div key={field} className="field">
              <label>{label}</label>
              <select value={form[field]} onChange={e => setForm(f => ({...f, [field]: e.target.value}))}>
                <option value="">— Select —</option>
                {options.map(o => <option key={o.id} value={o.id}>{o.value}</option>)}
              </select>
            </div>
          ))}
          <div className="form-actions">
            <button type="button" className="btn btn-outline" onClick={onCancel}>Cancel</button>
            <button type="submit" className="btn btn-primary">Save</button>
          </div>
        </form>
      </div>
    </div>
  )
}

function AppointmentCard({ appt, onUpdate }) {
  const APPT_STATUS_COLORS = { scheduled:'#eab308', completed:'#3b82f6', no_show:'#f97316', cancelled:'#ef4444' }
  return (
    <div className="appt-card">
      <div className="appt-date-block">
        <div className="appt-month">{format(new Date(appt.date), 'MMM').toUpperCase()}</div>
        <div className="appt-day">{format(new Date(appt.date), 'd')}</div>
      </div>
      <div className="appt-info">
        <div className="appt-time">{appt.time} · {appt.type_label || 'N/A'}</div>
        <div className="appt-meta">{appt.consultant_name || 'Unassigned'}{appt.is_last_appointment ? ' · ★ Last Appt' : ''}</div>
        {appt.notes && <div className="appt-notes">{appt.notes}</div>}
      </div>
      <div className="appt-right">
        <span style={{ fontSize:10, fontWeight:700, padding:'2px 8px', borderRadius:20, textTransform:'uppercase', background: APPT_STATUS_COLORS[appt.status]+'22', color: APPT_STATUS_COLORS[appt.status] }}>{appt.status.replace('_',' ')}</span>
        <select value={appt.status} onChange={e => onUpdate({ status: e.target.value })} className="appt-status-select">
          {['scheduled','completed','no_show','cancelled'].map(s => <option key={s} value={s}>{s.replace('_',' ')}</option>)}
        </select>
      </div>
    </div>
  )
}

function AppointmentForm({ consultants, types, onSave, onCancel }) {
  const [form, setForm] = useState({ date: '', time: '', type_id: '', consultant_id: '', is_last_appointment: 0, notes: '', status: 'scheduled' })
  return (
    <div className="appt-form">
      <form onSubmit={e => { e.preventDefault(); onSave(form) }}>
        <div className="field-row-inline">
          <div className="field"><label>Date *</label><input type="date" value={form.date} onChange={e => setForm(f => ({...f, date: e.target.value}))} required /></div>
          <div className="field"><label>Time *</label><input type="time" value={form.time} onChange={e => setForm(f => ({...f, time: e.target.value}))} required /></div>
        </div>
        <div className="field"><label>Type</label><select value={form.type_id} onChange={e => setForm(f => ({...f, type_id: e.target.value}))}><option value="">— Select —</option>{types.map(t => <option key={t.id} value={t.id}>{t.value}</option>)}</select></div>
        <div className="field"><label>Consultant</label><select value={form.consultant_id} onChange={e => setForm(f => ({...f, consultant_id: e.target.value}))}><option value="">— Select —</option>{consultants.filter(c => c.is_active).map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></div>
        <div className="field"><label><input type="checkbox" checked={!!form.is_last_appointment} onChange={e => setForm(f => ({...f, is_last_appointment: e.target.checked ? 1 : 0}))} /> Last appointment</label></div>
        <div className="field"><label>Notes</label><textarea value={form.notes} onChange={e => setForm(f => ({...f, notes: e.target.value}))} rows={2} /></div>
        <div className="form-actions">
          <button type="button" className="btn btn-outline" onClick={onCancel}>Cancel</button>
          <button type="submit" className="btn btn-primary">Save Appointment</button>
        </div>
      </form>
    </div>
  )
}
