// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

import React, { createContext, useContext, useState, useEffect } from 'react'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [token, setToken] = useState(() => sessionStorage.getItem('token'))
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (token) {
      window.ipc.invoke('auth:getSession', { token }).then(({ user }) => {
        setUser(user)
        setLoading(false)
      })
    } else {
      setLoading(false)
    }
  }, [token])

  const login = async (email, password) => {
    const result = await window.ipc.invoke('auth:login', { email, password })
    if (result.error) return result
    setToken(result.token)
    setUser(result.user)
    sessionStorage.setItem('token', result.token)
    return result
  }

  const logout = async () => {
    await window.ipc.invoke('auth:logout', { token })
    sessionStorage.removeItem('token')
    setToken(null)
    setUser(null)
  }

  const completeFirstRun = (result) => {
    setToken(result.token)
    setUser(result.user)
    sessionStorage.setItem('token', result.token)
  }

  return (
    <AuthContext.Provider value={{ user, token, loading, login, logout, completeFirstRun }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  return useContext(AuthContext)
}
