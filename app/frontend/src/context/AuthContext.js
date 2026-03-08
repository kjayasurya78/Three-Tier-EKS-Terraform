import React, { createContext, useContext, useState, useEffect } from 'react';
import { authAPI } from '../services/api';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser]       = useState(null);
  const [loading, setLoading] = useState(true);

  // On mount: restore user from localStorage if valid token exists
  useEffect(() => {
    const stored = localStorage.getItem('hm_user');
    const token  = localStorage.getItem('hm_token');
    if (stored && token) {
      try {
        setUser(JSON.parse(stored));
      } catch {
        localStorage.removeItem('hm_user');
        localStorage.removeItem('hm_token');
      }
    }
    setLoading(false);
  }, []);

  const login = async (email, password) => {
    const res  = await authAPI.login({ email, password });
    const { token, user: userData } = res.data;
    localStorage.setItem('hm_token', token);
    localStorage.setItem('hm_user',  JSON.stringify(userData));
    setUser(userData);
    return userData;
  };

  const register = async (name, email, password) => {
    const res  = await authAPI.register({ name, email, password });
    const { token, user: userData } = res.data;
    localStorage.setItem('hm_token', token);
    localStorage.setItem('hm_user',  JSON.stringify(userData));
    setUser(userData);
    return userData;
  };

  const logout = () => {
    localStorage.removeItem('hm_token');
    localStorage.removeItem('hm_user');
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, login, register, logout, loading }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
