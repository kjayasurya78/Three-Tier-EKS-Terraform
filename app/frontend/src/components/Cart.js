import React from 'react';
import { useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';

export default function Cart() {
  const { items, isOpen, setIsOpen, removeItem, updateQty, totalPrice } = useCart();
  const navigate = useNavigate();

  if (!isOpen) return null;

  const handleCheckout = () => {
    setIsOpen(false);
    navigate('/checkout');
  };

  return (
    <div>
      {/* Backdrop */}
      <div
        onClick={() => setIsOpen(false)}
        style={{ position:'fixed', inset:0, background:'rgba(0,0,0,0.4)', zIndex:199 }}
      />

      <div className="cart-overlay">
        <div className="cart-header">
          <h2>Shopping Cart ({items.length})</h2>
          <button className="cart-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>

        <div className="cart-items">
          {items.length === 0 ? (
            <div style={{ textAlign:'center', padding:'60px 0', color:'#888' }}>
              <div style={{ fontSize:48, marginBottom:16 }}>🛍</div>
              <p>Your cart is empty</p>
            </div>
          ) : (
            items.map((item) => (
              <div key={item.key} className="cart-item">
                <div className="cart-item-image">
                  {item.product.image_url
                    ? <img src={item.product.image_url} alt={item.product.name} style={{ width:'100%',height:'100%',objectFit:'cover' }} />
                    : '🛍'
                  }
                </div>
                <div className="cart-item-info">
                  <div className="cart-item-name">{item.product.name}</div>
                  <div className="cart-item-size">Size: {item.size}</div>
                  <div className="cart-item-price">₹{(item.product.price * item.quantity).toLocaleString()}</div>
                  <div className="cart-item-qty">
                    <button className="qty-btn" onClick={() => updateQty(item.key, item.quantity - 1)}>−</button>
                    <span>{item.quantity}</span>
                    <button className="qty-btn" onClick={() => updateQty(item.key, item.quantity + 1)}>+</button>
                    <button
                      onClick={() => removeItem(item.key)}
                      style={{ marginLeft:'auto', background:'none', color:'#e50010', fontSize:13 }}
                    >
                      Remove
                    </button>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>

        <div className="cart-footer">
          <div className="cart-total">
            <span>Total</span>
            <span>₹{totalPrice.toLocaleString()}</span>
          </div>
          <button
            className="btn-checkout"
            onClick={handleCheckout}
            disabled={items.length === 0}
          >
            Proceed to Checkout
          </button>
        </div>
      </div>
    </div>
  );
}
