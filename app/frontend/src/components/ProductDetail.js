import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { productsAPI } from '../services/api';
import { useCart } from '../context/CartContext';

const SIZES = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];

const EMOJI_MAP = {
  tops:    '👕',
  dresses: '👗',
  pants:   '👖',
  jackets: '🧥',
  shoes:   '👟',
  bags:    '👜',
  default: '🛍',
};

export default function ProductDetail() {
  const { id }          = useParams();
  const navigate         = useNavigate();
  const { addItem }      = useCart();
  const [product, setProduct] = useState(null);
  const [loading, setLoading] = useState(true);
  const [selectedSize, setSelectedSize] = useState('M');
  const [added, setAdded] = useState(false);

  useEffect(() => {
    productsAPI.getById(id)
      .then((res) => setProduct(res.data.product || res.data))
      .catch((err) => { console.error(err); navigate('/'); })
      .finally(() => setLoading(false));
  }, [id, navigate]);

  const handleAddToCart = () => {
    addItem(product, selectedSize, 1);
    setAdded(true);
    setTimeout(() => setAdded(false), 2000);
  };

  if (loading) return <div className="loading">Loading product...</div>;
  if (!product) return null;

  const emoji = EMOJI_MAP[product.category?.toLowerCase()] || EMOJI_MAP.default;
  const discountPct = product.original_price
    ? Math.round((1 - product.price / product.original_price) * 100)
    : null;

  return (
    <div className="product-detail">
      <div className="product-detail-image">
        {product.image_url
          ? <img src={product.image_url} alt={product.name} style={{ width:'100%',height:'100%',objectFit:'cover',borderRadius:4 }} />
          : <span>{emoji}</span>
        }
      </div>

      <div className="product-detail-info">
        <p style={{ fontSize: 13, color: '#888', textTransform: 'uppercase', letterSpacing: 1, marginBottom: 8 }}>
          {product.category}
        </p>
        <h1>{product.name}</h1>

        <div className="product-detail-price">
          ₹{product.price?.toLocaleString()}
          {product.original_price && (
            <>
              <span style={{ fontSize: 16, color: '#aaa', textDecoration: 'line-through', marginLeft: 10 }}>
                ₹{product.original_price?.toLocaleString()}
              </span>
              <span style={{ fontSize: 16, color: '#e50010', marginLeft: 8 }}>-{discountPct}%</span>
            </>
          )}
        </div>

        <p className="product-detail-description">
          {product.description || 'Premium quality fashion piece crafted for comfort and style.'}
        </p>

        <div style={{ marginBottom: 8, fontSize: 13, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5 }}>
          Select Size
        </div>
        <div className="size-selector">
          {SIZES.map((size) => (
            <button
              key={size}
              className={`size-btn${selectedSize === size ? ' active' : ''}`}
              onClick={() => setSelectedSize(size)}
            >
              {size}
            </button>
          ))}
        </div>

        <button className="btn-add-to-cart" onClick={handleAddToCart}>
          {added ? '✅ Added to Cart!' : 'Add to Cart'}
        </button>

        <div style={{ marginTop: 24, fontSize: 13, color: '#888' }}>
          <div>🚚 Free delivery on orders over ₹999</div>
          <div style={{ marginTop: 6 }}>↩️ Free returns within 30 days</div>
        </div>
      </div>
    </div>
  );
}
