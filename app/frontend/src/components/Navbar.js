import React from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';

export default function Navbar() {
  const { user, logout } = useAuth();
  const { totalItems, setIsOpen } = useCart();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  return (
    <nav className="navbar">
      <Link to="/" className="navbar-logo">H&M</Link>

      <ul className="navbar-links">
        <li><Link to="/">Ladies</Link></li>
        <li><Link to="/">Men</Link></li>
        <li><Link to="/">Kids</Link></li>
        <li><Link to="/">Sale</Link></li>
        <li><Link to="/">New Arrivals</Link></li>
      </ul>

      <div className="navbar-actions">
        {user ? (
          <>
            <span style={{ fontSize: 14, color: '#555' }}>Hi, {user.name}</span>
            <button className="btn-signin" onClick={handleLogout}>Sign Out</button>
          </>
        ) : (
          <>
            <Link to="/login">
              <button className="btn-signin">Sign In</button>
            </Link>
            <Link to="/register">
              <button style={{ background: 'none', fontSize: 14, fontWeight: 500 }}>
                Register
              </button>
            </Link>
          </>
        )}
        <button className="btn-cart" onClick={() => setIsOpen(true)}>
          🛍 Cart ({totalItems})
        </button>
      </div>
    </nav>
  );
}
