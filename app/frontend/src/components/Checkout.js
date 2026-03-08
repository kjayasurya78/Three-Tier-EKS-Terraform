import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import { ordersAPI } from '../services/api';

export default function Checkout() {
  const { items, totalPrice, clearCart } = useCart();
  const { user } = useAuth();
  const navigate = useNavigate();
  const [form, setForm] = useState({
    name:    user?.name || '',
    email:   user?.email || '',
    address: '',
    city:    '',
    pincode: '',
    phone:   '',
  });
  const [loading,  setLoading]  = useState(false);
  const [error,    setError]    = useState(null);

  const handleChange = (e) => setForm({ ...form, [e.target.name]: e.target.value });

  const handleSubmit = async () => {
    if (!form.address || !form.city || !form.pincode || !form.phone) {
      setError('Please fill in all required fields.');
      return;
    }
    setLoading(true);
    setError(null);
    try {
      await ordersAPI.create({
        items: items.map((i) => ({
          product_id: i.product.id,
          quantity:   i.quantity,
          size:       i.size,
          price:      i.product.price,
        })),
        total_amount:    totalPrice,
        shipping_address: `${form.address}, ${form.city} - ${form.pincode}`,
        phone:            form.phone,
      });
      clearCart();
      navigate('/', { state: { orderPlaced: true } });
    } catch (err) {
      setError(err.response?.data?.message || 'Order failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  if (items.length === 0) {
    navigate('/');
    return null;
  }

  const shipping = totalPrice > 999 ? 0 : 99;

  return (
    <div className="checkout-container">
      <div className="checkout-section">
        <h2>Shipping Details</h2>
        {error && <div className="auth-error">{error}</div>}

        {[
          { name:'name',    label:'Full Name',    type:'text' },
          { name:'email',   label:'Email',        type:'email' },
          { name:'phone',   label:'Phone',        type:'tel' },
          { name:'address', label:'Address',      type:'text' },
          { name:'city',    label:'City',         type:'text' },
          { name:'pincode', label:'PIN Code',     type:'text' },
        ].map(({ name, label, type }) => (
          <div className="form-group" key={name}>
            <label>{label}</label>
            <input
              type={type}
              name={name}
              value={form[name]}
              onChange={handleChange}
              placeholder={label}
            />
          </div>
        ))}
      </div>

      <div className="checkout-section">
        <h2>Order Summary</h2>
        {items.map((item) => (
          <div key={item.key} className="checkout-summary-item">
            <span>{item.product.name} × {item.quantity} ({item.size})</span>
            <span>₹{(item.product.price * item.quantity).toLocaleString()}</span>
          </div>
        ))}
        <div className="checkout-summary-item">
          <span>Shipping</span>
          <span>{shipping === 0 ? 'FREE' : `₹${shipping}`}</span>
        </div>
        <div className="checkout-total">
          <span>Total</span>
          <span>₹{(totalPrice + shipping).toLocaleString()}</span>
        </div>
        <button className="btn-place-order" onClick={handleSubmit} disabled={loading}>
          {loading ? 'Placing Order...' : 'Place Order'}
        </button>
        <p style={{ fontSize: 13, color: '#888', marginTop: 12, textAlign: 'center' }}>
          🔒 Secure checkout — demo mode (no real payment)
        </p>
      </div>
    </div>
  );
}
