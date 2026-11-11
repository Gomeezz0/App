import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireUser } from '../auth/routes.js';
import { verifyAccessToken } from '../auth/tokens.js';
import type { Db } from '../db.js';
import { parse } from '../errors.js';
import { listAlerts, reportAlert, voteOnAlert } from './service.js';
import { ALERT_TYPES } from './types.js';

const lat = z.coerce.number().min(-90).max(90);
const lon = z.coerce.number().min(-180).max(180);

const listQuery = z.object({
  lat,
  lon,
  radius: z.coerce.number().min(100).max(50_000).default(10_000),
});

const reportBody = z.object({
  type: z.enum(ALERT_TYPES),
  lat,
  lon,
  heading: z.number().min(0).max(360).optional(),
  country: z.string().length(2).optional(),
  reporterLat: lat,
  reporterLon: lon,
});

const voteBody = z.object({ vote: z.enum(['confirm', 'deny']), lat, lon });
const idParams = z.object({ id: z.uuid() });

export function registerAlertRoutes(app: FastifyInstance, db: Db) {
  // Lectura pública: el mapa funciona sin cuenta. Con sesión se añaden `mine` y `myVote`.
  app.get('/v1/alerts', async (req) => {
    const q = parse(listQuery, req.query);
    const header = req.headers.authorization;
    const userId = header?.startsWith('Bearer ') ? await verifyAccessToken(header.slice(7)) : null;
    return { alerts: await listAlerts(db, { lat: q.lat, lon: q.lon, radiusM: q.radius, userId }) };
  });

  app.post('/v1/alerts', async (req, reply) => {
    const userId = await requireUser(req);
    const result = await reportAlert(db, userId, parse(reportBody, req.body));
    reply.code(result.merged ? 200 : 201);
    return result;
  });

  app.post('/v1/alerts/:id/votes', async (req) => {
    const userId = await requireUser(req);
    const { id } = parse(idParams, req.params);
    return voteOnAlert(db, userId, id, parse(voteBody, req.body));
  });
}
