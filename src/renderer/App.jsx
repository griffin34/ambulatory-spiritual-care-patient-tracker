import React, { useEffect, useState } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth } from './hooks/useAuth'
import Sidebar from './components/Sidebar'
import Login from './pages/Login'
import FirstRun from './pages/FirstRun'
import WorkQueue from './pages/WorkQueue'
import PatientDetail from './pages/PatientDetail'
import Appointments from './pages/Appointments'
import Reports from './pages/Reports'
import Admin from './pages/Admin'

function AppRoutes() {
  const { user, loading } = useAuth()
  const [needsFirstRun, setNeedsFirstRun] = useState(null)

  useEffect(() => {
    window.ipc.invoke('auth:checkFirstRun').then(({ needsFirstRun }) => setNeedsFirstRun(needsFirstRun))
  }, [])

  if (loading || needsFirstRun === null) return <div className="loading-screen">Loading…</div>
  if (needsFirstRun) return <Routes><Route path="*" element={<FirstRun />} /></Routes>
  if (!user) return <Routes><Route path="*" element={<Login />} /></Routes>

  return (
    <div className="app-shell">
      <Sidebar />
      <main className="main">
        <Routes>
          <Route path="/" element={<Navigate to="/queue" replace />} />
          <Route path="/queue" element={<WorkQueue />} />
          <Route path="/queue/:id" element={<PatientDetail />} />
          <Route path="/appointments" element={<Appointments />} />
          <Route path="/reports" element={<Reports />} />
          {user.role === 'admin' && <Route path="/admin" element={<Admin />} />}
        </Routes>
      </main>
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <AppRoutes />
      </AuthProvider>
    </BrowserRouter>
  )
}
