import React, { useState, useEffect } from 'react';
import ProductCard from './ProductCard';
import FilterSidebar from './FilterSidebar';
import { productsAPI } from '../services/api';

export default function ProductGrid() {
  const [products, setProducts] = useState([]);
  const [loading,  setLoading]  = useState(true);
  const [error,    setError]    = useState(null);
  const [filters,  setFilters]  = useState({
    categories: [],
    sizes: [],
    minPrice: '',
    maxPrice: '',
  });
  const [sortBy, setSortBy] = useState('newest');

  useEffect(() => {
    const fetchProducts = async () => {
      setLoading(true);
      try {
        const params = { sort: sortBy };
        if (filters.categories.length)  params.category  = filters.categories.join(',');
        if (filters.sizes.length)        params.size      = filters.sizes.join(',');
        if (filters.minPrice)            params.min_price = filters.minPrice;
        if (filters.maxPrice)            params.max_price = filters.maxPrice;
        const res = await productsAPI.getAll(params);
        setProducts(res.data.products || res.data);
      } catch (err) {
        setError('Failed to load products. Please try again.');
        console.error('Product fetch error:', err);
      } finally {
        setLoading(false);
      }
    };
    fetchProducts();
  }, [filters, sortBy]);

  if (loading) return <div className="loading">Loading products...</div>;
  if (error)   return <div className="loading" style={{ color: '#e50010' }}>{error}</div>;

  return (
    <div className="shop-layout">
      <FilterSidebar filters={filters} onChange={setFilters} />
      <section className="product-grid-section">
        <div className="product-grid-header">
          <h2>{products.length} Products</h2>
          <select
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value)}
            style={{ padding: '8px 12px', border: '1px solid #ddd', borderRadius: 2, fontSize: 14 }}
          >
            <option value="newest">Newest First</option>
            <option value="price_asc">Price: Low to High</option>
            <option value="price_desc">Price: High to Low</option>
            <option value="popular">Most Popular</option>
          </select>
        </div>
        {products.length === 0 ? (
          <p style={{ color: '#888', textAlign: 'center', padding: '60px 0' }}>
            No products match your filters.
          </p>
        ) : (
          <div className="product-grid">
            {products.map((p) => (
              <ProductCard key={p.id} product={p} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
