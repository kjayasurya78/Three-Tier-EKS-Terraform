require('dotenv').config();
const express    = require('express');
const cors       = require('cors');
const helmet     = require('helmet');
const morgan     = require('morgan');
const { Pool }   = require('pg');

const authRoutes     = require('./routes/auth');
const productRoutes  = require('./routes/products');
const orderRoutes    = require('./routes/orders');
const healthRoutes   = require('./routes/health');
const { metricsMiddleware, metricsEndpoint } = require('./metrics/prometheus');

const app  = express();
const PORT = process.env.PORT || 5000;

// ── Database Connection Pool ─────────────────────────────────────────────────
const pool = new Pool({
  host:     process.env.DB_HOST     || 'postgres-service',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'hmshop',
  user:     process.env.DB_USER     || 'hmuser',
  password: process.env.DB_PASSWORD || 'changeme',
  max:      20,
  idleTimeoutMillis:    30000,
  connectionTimeoutMillis: 5000,
});

// Make pool available to routes
app.locals.db = pool;

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET','POST','PUT','DELETE','OPTIONS'],
  allowedHeaders: ['Content-Type','Authorization'],
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan('combined'));
app.use(metricsMiddleware);

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/api/auth',     authRoutes);
app.use('/api/products', productRoutes);
app.use('/api/orders',   orderRoutes);
app.use('/api/health',   healthRoutes);
app.get('/metrics',      metricsEndpoint);

// ── 404 Handler ───────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ message: 'Route not found' });
});

// ── Global Error Handler ──────────────────────────────────────────────────────
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ message: 'Internal server error' });
});

// ── Start Server ──────────────────────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`H&M Backend API running on port ${PORT}`);
  console.log(`DB host: ${process.env.DB_HOST || 'postgres-service'}`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received — shutting down gracefully');
  await pool.end();
  process.exit(0);
});
