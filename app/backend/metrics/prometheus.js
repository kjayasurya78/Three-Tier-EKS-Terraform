const client = require('prom-client');

// ── Collect default Node.js metrics ──────────────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register });

// ── Custom HTTP metrics ───────────────────────────────────────────────────────
const httpRequestDuration = new client.Histogram({
  name:    'http_request_duration_seconds',
  help:    'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
});

const httpRequestTotal = new client.Counter({
  name:    'http_requests_total',
  help:    'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});

const activeConnections = new client.Gauge({
  name:    'http_active_connections',
  help:    'Number of active HTTP connections',
});

register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestTotal);
register.registerMetric(activeConnections);

// ── Middleware ────────────────────────────────────────────────────────────────
function metricsMiddleware(req, res, next) {
  const start = Date.now();
  activeConnections.inc();

  res.on('finish', () => {
    const duration    = (Date.now() - start) / 1000;
    const route       = req.route?.path || req.path || 'unknown';
    const method      = req.method;
    const status_code = String(res.statusCode);

    httpRequestDuration.observe({ method, route, status_code }, duration);
    httpRequestTotal.inc({ method, route, status_code });
    activeConnections.dec();
  });

  next();
}

// ── Metrics endpoint handler ──────────────────────────────────────────────────
async function metricsEndpoint(req, res) {
  res.set('Content-Type', register.contentType);
  res.send(await register.metrics());
}

module.exports = { metricsMiddleware, metricsEndpoint, register };
