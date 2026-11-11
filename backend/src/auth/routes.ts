import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { withTx, type Db } from '../db.js';
import { HttpError, parse } from '../errors.js';
import { hashPassword, verifyPassword } from './passwords.js';
import {
  consumeRefreshToken,
  issueRefreshToken,
  revokeRefreshToken,
  signAccessToken,
  verifyAccessToken,
} from './tokens.js';

const email = z.string().trim().toLowerCase().pipe(z.email().max(254));
const password = z.string().min(10, 'mínimo 10 caracteres').max(200);
const displayName = z.string().trim().min(2).max(40);

const registerBody = z.object({ email, password, displayName });
const loginBody = z.object({ email, password: z.string().min(1).max(200) });
const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
const patchBody = z.object({ displayName });
const deleteBody = z.object({ password: z.string().min(1).max(200) });

/** Extrae el usuario del encabezado Authorization o lanza 401. */
export async function requireUser(req: FastifyRequest): Promise<string> {
  const header = req.headers.authorization;
  const token = header?.startsWith('Bearer ') ? header.slice(7) : null;
  const userId = token ? await verifyAccessToken(token) : null;
  if (!userId) throw new HttpError(401, 'unauthorized', 'Sesión no válida o caducada');
  return userId;
}

async function session(db: Db, userId: string) {
  return {
    accessToken: await signAccessToken(userId),
    refreshToken: await issueRefreshToken(db, userId),
    expiresIn: config.accessTokenTtlSeconds,
  };
}

async function profile(db: Db, userId: string) {
  const { rows } = await db.query(
    `SELECT u.id, u.email, u.display_name, u.reputation, u.created_at,
            (SELECT count(*)::int FROM alerts a WHERE a.reporter_id = u.id) AS reports,
            (SELECT count(*)::int FROM alert_votes v JOIN alerts a ON a.id = v.alert_id
              WHERE a.reporter_id = u.id AND v.vote = 'confirm') AS confirmations_received,
            (SELECT count(*)::int FROM alert_votes v WHERE v.user_id = u.id) AS votes_cast
       FROM users u WHERE u.id = $1`,
    [userId],
  );
  const u = rows[0];
  if (!u) throw new HttpError(401, 'unauthorized', 'La cuenta ya no existe');
  return {
    id: u.id,
    email: u.email,
    displayName: u.display_name,
    reputation: u.reputation,
    createdAt: u.created_at,
    stats: { reports: u.reports, confirmationsReceived: u.confirmations_received, votesCast: u.votes_cast },
  };
}

export function registerAuthRoutes(app: FastifyInstance, db: Db) {
  const authLimit = { config: { rateLimit: { max: config.authRateLimitPerMinute, timeWindow: '1 minute' } } };

  app.post('/v1/auth/register', authLimit, async (req, reply) => {
    const body = parse(registerBody, req.body);
    const hash = await hashPassword(body.password);
    const { rows } = await db.query(
      `INSERT INTO users (email, password_hash, display_name) VALUES ($1, $2, $3)
       ON CONFLICT (lower(email)) DO NOTHING RETURNING id`,
      [body.email, hash, body.displayName],
    );
    if (!rows[0]) throw new HttpError(409, 'email_taken', 'Ya existe una cuenta con ese correo');
    reply.code(201);
    return { ...(await session(db, rows[0].id)), user: await profile(db, rows[0].id) };
  });

  app.post('/v1/auth/login', authLimit, async (req) => {
    const body = parse(loginBody, req.body);
    const { rows } = await db.query('SELECT id, password_hash FROM users WHERE lower(email) = $1', [body.email]);
    const user = rows[0];
    // Se verifica siempre algo para no revelar por tiempo si el correo existe.
    const ok = user
      ? await verifyPassword(body.password, user.password_hash)
      : (await hashPassword(body.password), false);
    if (!ok) throw new HttpError(401, 'invalid_credentials', 'Correo o contraseña incorrectos');
    return { ...(await session(db, user.id)), user: await profile(db, user.id) };
  });

  app.post('/v1/auth/refresh', authLimit, async (req) => {
    const body = parse(refreshBody, req.body);
    const userId = await consumeRefreshToken(db, body.refreshToken);
    if (!userId) throw new HttpError(401, 'invalid_refresh_token', 'Sesión caducada');
    return session(db, userId);
  });

  app.post('/v1/auth/logout', async (req, reply) => {
    const body = parse(refreshBody, req.body);
    await revokeRefreshToken(db, body.refreshToken);
    reply.code(204);
  });

  app.get('/v1/me', async (req) => profile(db, await requireUser(req)));

  app.patch('/v1/me', async (req) => {
    const userId = await requireUser(req);
    const body = parse(patchBody, req.body);
    await db.query('UPDATE users SET display_name = $2 WHERE id = $1', [userId, body.displayName]);
    return profile(db, userId);
  });

  // Borrado de cuenta. Los avisos del usuario se conservan anónimos (reporter_id pasa a NULL).
  app.delete('/v1/me', async (req, reply) => {
    const userId = await requireUser(req);
    const body = parse(deleteBody, req.body);
    await withTx(db, async (tx) => {
      const { rows } = await tx.query('SELECT password_hash FROM users WHERE id = $1 FOR UPDATE', [userId]);
      if (!rows[0] || !(await verifyPassword(body.password, rows[0].password_hash))) {
        throw new HttpError(403, 'invalid_credentials', 'Contraseña incorrecta');
      }
      await tx.query('DELETE FROM users WHERE id = $1', [userId]);
    });
    reply.code(204);
  });
}
