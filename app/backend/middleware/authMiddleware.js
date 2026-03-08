const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'hm-shop-super-secret-jwt-key-2024';

/**
 * requireAuth — Middleware to verify JWT token
 * Attaches decoded user payload to req.user
 */
function requireAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Authentication required' });
  }
  const token = header.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ message: 'Invalid or expired token' });
  }
}

/**
 * requireAdmin — Middleware to restrict routes to admin users
 * Must be used after requireAuth
 */
function requireAdmin(req, res, next) {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ message: 'Admin access required' });
  }
  next();
}

module.exports = { requireAuth, requireAdmin, JWT_SECRET };
