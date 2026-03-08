import React from 'react';

const CATEGORIES = ['Tops', 'Dresses', 'Pants', 'Jackets', 'Shoes', 'Bags'];
const SIZES      = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];

export default function FilterSidebar({ filters, onChange }) {
  const toggleCategory = (cat) => {
    const cats = filters.categories || [];
    const next = cats.includes(cat)
      ? cats.filter((c) => c !== cat)
      : [...cats, cat];
    onChange({ ...filters, categories: next });
  };

  const toggleSize = (size) => {
    const sizes = filters.sizes || [];
    const next  = sizes.includes(size)
      ? sizes.filter((s) => s !== size)
      : [...sizes, size];
    onChange({ ...filters, sizes: next });
  };

  return (
    <aside className="filter-sidebar">
      <h3>Filters</h3>

      <div className="filter-group">
        <h3>Category</h3>
        {CATEGORIES.map((cat) => (
          <label key={cat}>
            <input
              type="checkbox"
              checked={(filters.categories || []).includes(cat)}
              onChange={() => toggleCategory(cat)}
            />
            {cat}
          </label>
        ))}
      </div>

      <div className="filter-group">
        <h3>Size</h3>
        {SIZES.map((size) => (
          <label key={size}>
            <input
              type="checkbox"
              checked={(filters.sizes || []).includes(size)}
              onChange={() => toggleSize(size)}
            />
            {size}
          </label>
        ))}
      </div>

      <div className="filter-group">
        <h3>Price Range (₹)</h3>
        <div className="price-range">
          <input
            type="number"
            placeholder="Min"
            value={filters.minPrice || ''}
            onChange={(e) => onChange({ ...filters, minPrice: e.target.value })}
          />
          <span>–</span>
          <input
            type="number"
            placeholder="Max"
            value={filters.maxPrice || ''}
            onChange={(e) => onChange({ ...filters, maxPrice: e.target.value })}
          />
        </div>
      </div>

      <button
        onClick={() => onChange({ categories: [], sizes: [], minPrice: '', maxPrice: '' })}
        style={{ background: 'none', fontSize: 13, color: '#e50010', textDecoration: 'underline', marginTop: 8 }}
      >
        Clear all filters
      </button>
    </aside>
  );
}
