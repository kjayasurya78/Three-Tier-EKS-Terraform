const express = require('express');
const router  = express.Router();

// GET /api/health — ALB health check + deep DB check
router.get('/', async (req, res) => {
  const db = req.app.locals.db;
  let   dbStatus = 'unknown';
  let   dbLatency = null;

  try {
    const t0 = Date.now();
    await db.query('SELECT 1');
    dbLatency = Date.now() - t0;
    dbStatus  = 'connected';
  } catch (err) {
    dbStatus = `error: ${err.message}`;
  }

  const healthy = dbStatus === 'connected';
  res.status(healthy ? 200 : 503).json({
    status:    healthy ? 'healthy' : 'degraded',
    timestamp: new Date().toISOString(),
    service:   'hm-backend',
    version:   process.env.npm_package_version || '1.0.0',
    database: {
      status:  dbStatus,
      latency_ms: dbLatency,
    },
    uptime_seconds: Math.floor(process.uptime()),
  });
});

module.exports = router;
