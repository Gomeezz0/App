import { randomBytes } from 'node:crypto';

const env = process.env;
const isProd = env.NODE_ENV === 'production';

function jwtSecret(): Uint8Array {
  const s = env.JWT_SECRET;
  if (s && s.length >= 32) return new TextEncoder().encode(s);
  if (isProd) throw new Error('JWT_SECRET (>= 32 caracteres) es obligatorio en producción');
  // En desarrollo se genera uno efímero: las sesiones no sobreviven a un reinicio.
  return randomBytes(32);
}

export const config = {
  isProd,
  port: Number(env.PORT ?? 8080),
  host: env.HOST ?? '0.0.0.0',
  databaseUrl: env.DATABASE_URL ?? 'postgres://nex:nex@localhost:5432/nex',
  jwtSecret: jwtSecret(),
  accessTokenTtlSeconds: 15 * 60,
  refreshTokenTtlDays: 60,
  /** Peticiones por minuto y por IP. Los tests lo elevan. */
  rateLimitPerMinute: Number(env.RATE_LIMIT_PER_MINUTE ?? 120),
  authRateLimitPerMinute: Number(env.AUTH_RATE_LIMIT_PER_MINUTE ?? 10),
};
