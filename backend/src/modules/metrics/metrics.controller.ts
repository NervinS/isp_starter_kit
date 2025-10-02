import { Controller, Get, Header, Req } from '@nestjs/common';
import { Registry, collectDefaultMetrics, Histogram, Counter } from 'prom-client';

// Registro y métricas básicas (singleton de módulo)
const registry = new Registry();
collectDefaultMetrics({ register: registry });

const httpRequests = new Counter({
  name: 'http_requests_total',
  help: 'Total de requests HTTP',
  labelNames: ['method', 'route', 'status'],
  registers: [registry],
});

const httpDuration = new Histogram({
  name: 'http_request_duration_ms',
  help: 'Histograma de latencia por ruta',
  labelNames: ['method', 'route', 'status'],
  buckets: [10, 25, 50, 100, 250, 500, 1000, 2000, 5000],
  registers: [registry],
});

// Middleware mínimo por-request (se puede mover a interceptor si querés)
function attachMetrics(req: any, res: any, next: any) {
  const start = Date.now();
  const origEnd = res.end;
  res.end = function (...args: any[]) {
    const ms = Date.now() - start;
    const route = (req.route?.path || req.originalUrl || req.url || 'unknown')
      .replace(/\?.*$/, '');
    const status = res.statusCode?.toString() || '0';
    const method = req.method;

    httpRequests.labels(method, route, status).inc(1);
    httpDuration.labels(method, route, status).observe(ms);

    return origEnd.apply(this, args as any);
  };
  next();
}

@Controller('metrics')
export class MetricsController {
  @Get()
  @Header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
  async getMetrics(@Req() req: any): Promise<string> {
    // Adjunta hook sólo si no lo hicimos antes en la app (simple por ahora)
    if (!req.app?.locals?.metricsAttached) {
      req.app.locals = req.app.locals || {};
      req.app.locals.metricsAttached = true;
      req.app.use(attachMetrics);
    }
    return registry.metrics();
  }
}
