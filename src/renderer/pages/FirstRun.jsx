import React, { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'

export default function FirstRun() {
  const [form, setForm] = useState({ name: '', email: '', password: '', confirm: '' }) // email used as User ID
  const [error, setError] = useState('')
  const { completeFirstRun } = useAuth()
  const navigate = useNavigate()

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (form.password !== form.confirm) { setError('Passwords do not match'); return }
    try {
      const result = await window.ipc.invoke('auth:createFirstAdmin', { name: form.name, email: form.email, password: form.password })
      completeFirstRun(result)
      navigate('/queue')
    } catch (err) {
      setError(err.message || 'Failed to create account')
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-logo">
          <div className="login-app-name">Welcome</div>
          <div className="login-app-subtitle">Create your admin account to get started</div>
        </div>
        <form onSubmit={handleSubmit}>
          {error && <div className="login-error">{error}</div>}
          {['name','email','password','confirm'].map(field => (
            <div className="field" key={field}>
              <label>{field === 'confirm' ? 'Confirm Password' : field === 'email' ? 'User ID' : field.charAt(0).toUpperCase() + field.slice(1)}</label>
              <input
                type={field.includes('pass') || field === 'confirm' ? 'password' : 'text'}
                value={form[field]}
                onChange={e => setForm(f => ({...f, [field]: e.target.value}))}
                required
              />
            </div>
          ))}
          <button type="submit" className="btn btn-primary btn-full">Create Account</button>
        </form>
      </div>
    </div>
  )
}
