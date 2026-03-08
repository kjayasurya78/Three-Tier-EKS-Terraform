import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

export default function Register() {
  const [name,     setName]     = useState('');
  const [email,    setEmail]    = useState('');
  const [password, setPassword] = useState('');
  const [confirm,  setConfirm]  = useState('');
  const [error,    setError]    = useState(null);
  const [loading,  setLoading]  = useState(false);
  const { register } = useAuth();
  const navigate      = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError(null);
    if (password !== confirm) { setError('Passwords do not match.'); return; }
    if (password.length < 6)  { setError('Password must be at least 6 characters.'); return; }
    setLoading(true);
    try {
      await register(name, email, password);
      navigate('/');
    } catch (err) {
      setError(err.response?.data?.message || 'Registration failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-container">
      <h2>Create Account</h2>
      {error && <div className="auth-error">{error}</div>}
      <form onSubmit={handleSubmit}>
        {[
          { label:'Full Name',       value: name,     setter: setName,     type:'text' },
          { label:'Email',           value: email,    setter: setEmail,    type:'email' },
          { label:'Password',        value: password, setter: setPassword, type:'password' },
          { label:'Confirm Password',value: confirm,  setter: setConfirm,  type:'password' },
        ].map(({ label, value, setter, type }) => (
          <div className="form-group" key={label}>
            <label>{label}</label>
            <input
              type={type}
              value={value}
              onChange={(e) => setter(e.target.value)}
              placeholder={label}
              required
            />
          </div>
        ))}
        <button type="submit" className="auth-submit" disabled={loading}>
          {loading ? 'Creating Account...' : 'Create Account'}
        </button>
      </form>
      <div className="auth-switch">
        Already have an account? <Link to="/login">Sign In</Link>
      </div>
    </div>
  );
}
