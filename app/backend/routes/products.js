const express = require('express');
const router  = express.Router();

// ── GET /api/products ─────────────────────────────────────────────────────────
router.get('/', async (req, res) => {
  const db = req.app.locals.db;
  const { category, min_price, max_price, sort, search } = req.query;

  let query  = 'SELECT * FROM products WHERE 1=1';
  const params = [];
  let idx = 1;

  if (category) {
    const cats = category.split(',').map(c => c.toLowerCase());
    query += ` AND LOWER(category) = ANY($${idx++}::text[])`;
    params.push(cats);
  }
  if (min_price) { query += ` AND price >= $${idx++}`; params.push(Number(min_price)); }
  if (max_price) { query += ` AND price <= $${idx++}`; params.push(Number(max_price)); }
  if (search)    { query += ` AND (LOWER(name) LIKE $${idx++} OR LOWER(description) LIKE $${idx-1})`; params.push(`%${search.toLowerCase()}%`); }

  const ORDER_MAP = {
    price_asc:  'ORDER BY price ASC',
    price_desc: 'ORDER BY price DESC',
    newest:     'ORDER BY created_at DESC',
    popular:    'ORDER BY id ASC',
  };
  query += ` ${ORDER_MAP[sort] || ORDER_MAP.newest}`;

  try {
    const result = await db.query(query, params);
    res.json({ products: result.rows, total: result.rows.length });
  } catch (err) {
    console.error('Products fetch error:', err);
    res.status(500).json({ message: 'Failed to fetch products' });
  }
});

// ── GET /api/products/categories ─────────────────────────────────────────────
router.get('/categories', async (req, res) => {
  const db = req.app.locals.db;
  try {
    const result = await db.query('SELECT DISTINCT category FROM products ORDER BY category');
    res.json({ categories: result.rows.map(r => r.category) });
  } catch (err) {
    res.status(500).json({ message: 'Failed to fetch categories' });
  }
});

// ── GET /api/products/:id ─────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  const db = req.app.locals.db;
  const { id } = req.params;
  if (isNaN(id)) return res.status(400).json({ message: 'Invalid product ID' });

  try {
    const result = await db.query('SELECT * FROM products WHERE id = $1', [parseInt(id)]);
    if (result.rows.length === 0) return res.status(404).json({ message: 'Product not found' });
    res.json({ product: result.rows[0] });
  } catch (err) {
    console.error('Product fetch error:', err);
    res.status(500).json({ message: 'Failed to fetch product' });
  }
});

module.exports = router;
