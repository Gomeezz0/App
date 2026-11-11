import Fastify, { type FastifyInstance } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { registerAlertRoutes } from './alerts/routes.js';
import { registerAuthRoutes } from './auth/routes.js';
import { config } from './config.js';
import type { Db } from './db.js';
import { HttpError } from './errors.js';

export async function buildApp(db: Db, opts: { logger?: boolean } = {}): Promise<FastifyInstance> {
  const app = Fastify({ logger: opts.logger ?? false, trustProxy: true, bodyLimit: 16 * 1024 });

  await app.register(rateLimit, { max: config.rateLimitPerMinute, timeWindow: '1 minute' });

  app.setErrorHandler((err: Error & { statusCode?: number; code?: string }, req, reply) => {
    if (err instanceof HttpError) {
      return reply.code(err.statusCode).send({ error: { code: err.code, message: err.message } });
    }
    const status = err.statusCode && err.statusCode >= 400 && err.statusCode < 500 ? err.statusCode : 500;
    if (status === 500) req.log.error(err);
    const code = status === 429 ? 'rate_limited' : status === 500 ? 'internal_error' : 'bad_request';
    const message = status === 500 ? 'Error interno' : err.message;
    return reply.code(status).send({ error: { code, message } });
  });

  app.setNotFoundHandler((_req, reply) =>
    reply.code(404).send({ error: { code: 'not_found', message: 'Ruta no encontrada' } }),
  );

  app.get('/health', async () => {
    await db.query('SELECT 1');
    return { status: 'ok' };
  });

  registerAuthRoutes(app, db);
  registerAlertRoutes(app, db);
  return app;
}
