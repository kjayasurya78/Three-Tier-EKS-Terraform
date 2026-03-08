const express = require('express');
const { requireAuth } = require('../middleware/authMiddleware');
const router  = express.Router();

// ── POST /api/orders ──────────────────────────────────────────────────────────
router.post('/', requireAuth, async (req, res) => {
  const db = req.app.locals.db;
  const { items, total_amount, shipping_address, phone } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ message: 'Order must contain at least one item' });
  }
  if (!total_amount || total_amount <= 0) {
    return res.status(400).json({ message: 'Invalid total amount' });
  }

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const orderRes = await client.query(
      'INSERT INTO orders (user_id, total_amount, shipping_address, phone) VALUES ($1, $2, $3, $4) RETURNING *',
      [req.user.id, total_amount, shipping_address, phone]
    );
    const order = orderRes.rows[0];

    for (const item of items) {
      await client.query(
        'INSERT INTO order_items (order_id, product_id, quantity, size, price) VALUES ($1, $2, $3, $4, $5)',
        [order.id, item.product_id, item.quantity, item.size, item.price]
      );
    }

    await client.query('COMMIT');
    res.status(201).json({ order, message: 'Order placed successfully' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Order create error:', err);
    res.status(500).json({ message: 'Failed to create order' });
  } finally {
    client.release();
  }
});

// ── GET /api/orders/mine ──────────────────────────────────────────────────────
router.get('/mine', requireAuth, async (req, res) => {
  const db = req.app.locals.db;
  try {
    const result = await db.query(
      `SELECT o.*, json_agg(
         json_build_object(
           'id', oi.id, 'product_id', oi.product_id,
           'quantity', oi.quantity, 'size', oi.size, 'price', oi.price,
           'product_name', p.name
         )
       ) AS items
       FROM orders o
       LEFT JOIN order_items oi ON oi.order_id = o.id
       LEFT JOIN products p     ON p.id = oi.product_id
       WHERE o.user_id = $1
       GROUP BY o.id
       ORDER BY o.created_at DESC`,
      [req.user.id]
    );
    res.json({ orders: result.rows });
  } catch (err) {
    console.error('Orders fetch error:', err);
    res.status(500).json({ message: 'Failed to fetch orders' });
  }
});

// ── GET /api/orders/:id ───────────────────────────────────────────────────────
router.get('/:id', requireAuth, async (req, res) => {
  const db = req.app.locals.db;
  const { id } = req.params;
  if (isNaN(id)) return res.status(400).json({ message: 'Invalid order ID' });

  try {
    const result = await db.query(
      `SELECT o.*, json_agg(
         json_build_object(
           'id', oi.id, 'product_id', oi.product_id,
           'quantity', oi.quantity, 'size', oi.size, 'price', oi.price,
           'product_name', p.name
         )
       ) AS items
       FROM orders o
       LEFT JOIN order_items oi ON oi.order_id = o.id
       LEFT JOIN products p     ON p.id = oi.product_id
       WHERE o.id = $1 AND o.user_id = $2
       GROUP BY o.id`,
      [parseInt(id), req.user.id]
    );
    if (result.rows.length === 0) return res.status(404).json({ message: 'Order not found' });
    res.json({ order: result.rows[0] });
  } catch (err) {
    console.error('Order fetch error:', err);
    res.status(500).json({ message: 'Failed to fetch order' });
  }
});

module.exports = router;
