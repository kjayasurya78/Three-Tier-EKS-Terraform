import React from 'react';
import { useNavigate } from 'react-router-dom';

const EMOJI_MAP = {
  tops:     '👕',
  dresses:  '👗',
  pants:    '👖',
  jackets:  '🧥',
  shoes:    '👟',
  bags:     '👜',
  default:  '🛍',
};

export default function ProductCard({ product }) {
  const navigate = useNavigate();

  const discountPct = product.original_price
    ? Math.round((1 - product.price / product.original_price) * 100)
    : null;

  const emoji = EMOJI_MAP[product.category?.toLowerCase()] || EMOJI_MAP.default;

  return (
    <div className="product-card" onClick={() => navigate(`/products/${product.id}`)}>
      <div className="product-card-image">
        {product.image_url
          ? <img src={product.image_url} alt={product.name} />
          : <span>{emoji}</span>
        }
      </div>
      <div className="product-card-info">
        <div className="product-card-name">{product.name}</div>
        <div className="product-card-type">{product.category}</div>
        <div>
          <span className="product-card-price">₹{product.price?.toLocaleString()}</span>
          {product.original_price && (
            <>
              <span className="product-card-original-price">
                ₹{product.original_price?.toLocaleString()}
              </span>
              <span className="product-card-discount">-{discountPct}%</span>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
