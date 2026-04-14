import React from 'react'
import { NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'

export default function Sidebar() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  const handleLogout = async () => {
    await logout()
    navigate('/login')
  }

  const initials = user ? user.name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase() : '?'

  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <div className="app-name">Ambulatory</div>
        <div className="app-subtitle">Patient Tracking</div>
      </div>
      <nav className="sidebar-nav">
        <div className="nav-section">Main</div>
        <NavLink className={({isActive}) => `nav-item${isActive?' active':''}`} to="/queue">
          <span className="icon">☰</span> Work Queue
        </NavLink>
        <NavLink className={({isActive}) => `nav-item${isActive?' active':''}`} to="/appointments">
          <span className="icon">📅</span> Appointments
        </NavLink>
        <NavLink className={({isActive}) => `nav-item${isActive?' active':''}`} to="/reports">
          <span className="icon">📊</span> Reports
        </NavLink>
        {user?.role === 'admin' && <>
          <div className="nav-section">Admin</div>
          <NavLink className={({isActive}) => `nav-item${isActive?' active':''}`} to="/admin">
            <span className="icon">👥</span> Users &amp; Settings
          </NavLink>
        </>}
      </nav>
      <div className="sidebar-footer">
        <div className="user-info">
          <div className="avatar">{initials}</div>
          <div className="user-name">{user?.name}</div>
        </div>
        <button className="logout-btn" onClick={handleLogout}>Sign out</button>
      </div>
    </aside>
  )
}
