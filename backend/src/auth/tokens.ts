import { createHash, randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import { config } from '../config.js';
import type { Db, Tx } from '../db.js';

const ISSUER = 'nex';

export async function signAccessToken(userId: string): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime(`${config.accessTokenTtlSeconds}s`)
    .sign(config.jwtSecret);
}

export async function verifyAccessToken(token: string): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, config.jwtSecret, { issuer: ISSUER, algorithms: ['HS256'] });
    return payload.sub ?? null;
  } catch {
    return null;
  }
}

const sha256 = (value: string) => createHash('sha256').update(value).digest('hex');

/** Crea un refresh token opaco. En base de datos solo se guarda su hash. */
export async function issueRefreshToken(db: Db | Tx, userId: string): Promise<string> {
  const token = randomBytes(32).toString('base64url');
  await db.query(
    `INSERT INTO refresh_tokens (token_hash, user_id, expires_at)
     VALUES ($1, $2, now() + make_interval(days => $3))`,
    [sha256(token), userId, config.refreshTokenTtlDays],
  );
  return token;
}

/** Consume un refresh token (un solo uso). Devuelve el usuario o null si no es válido. */
export async function consumeRefreshToken(db: Db | Tx, token: string): Promise<string | null> {
  const { rows } = await db.query(
    'DELETE FROM refresh_tokens WHERE token_hash = $1 RETURNING user_id, expires_at > now() AS valid',
    [sha256(token)],
  );
  const row = rows[0];
  return row?.valid ? (row.user_id as string) : null;
}

export async function revokeRefreshToken(db: Db | Tx, token: string): Promise<void> {
  await db.query('DELETE FROM refresh_tokens WHERE token_hash = $1', [sha256(token)]);
}
