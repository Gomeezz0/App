import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import type { FastifyInstance } from 'fastify';

process.env.RATE_LIMIT_PER_MINUTE = '100000';
process.env.AUTH_RATE_LIMIT_PER_MINUTE = '100000';
const url = process.env.TEST_DATABASE_URL ?? 'postgres://nex:nex@localhost:5432/nex_test';

const { createPool, migrate } = await import('../src/db.js');
const { buildApp } = await import('../src/app.js');

const db = createPool(url);
let app: FastifyInstance;

before(async () => {
  await db.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate(db);
  app = await buildApp(db);
});

after(async () => {
  await app.close();
  await db.end();
});

// Puerta del Sol, Madrid.
const SOL = { lat: 40.4168, lon: -3.7038 };

interface Session {
  token: string;
  refresh: string;
  id: string;
}

let counter = 0;
/** Crea un usuario. Por defecto se le envejece la cuenta para que su voto pese como el de un usuario normal. */
async function user(opts: { fresh?: boolean; reputation?: number } = {}): Promise<Session> {
  const res = await app.inject({
    method: 'POST',
    url: '/v1/auth/register',
    payload: { email: `u${++counter}@nex.test`, password: 'contraseña-larga-1', displayName: `Piloto ${counter}` },
  });
  assert.equal(res.statusCode, 201, res.body);
  const body = res.json();
  if (!opts.fresh) await db.query(`UPDATE users SET created_at = now() - interval '30 days' WHERE id = $1`, [body.user.id]);
  if (opts.reputation !== undefined) {
    await db.query('UPDATE users SET reputation = $2 WHERE id = $1', [body.user.id, opts.reputation]);
  }
  return { token: body.accessToken, refresh: body.refreshToken, id: body.user.id };
}

const auth = (s: Session) => ({ authorization: `Bearer ${s.token}` });

function report(s: Session, type: string, at = SOL, extra: Record<string, unknown> = {}) {
  return app.inject({
    method: 'POST',
    url: '/v1/alerts',
    headers: auth(s),
    payload: { type, ...at, reporterLat: at.lat, reporterLon: at.lon, country: 'ES', ...extra },
  });
}

function vote(s: Session, id: string, v: 'confirm' | 'deny', at = SOL) {
  return app.inject({ method: 'POST', url: `/v1/alerts/${id}/votes`, headers: auth(s), payload: { vote: v, ...at } });
}

async function list(s: Session | null, at = SOL, radius = 5000) {
  const res = await app.inject({
    method: 'GET',
    url: `/v1/alerts?lat=${at.lat}&lon=${at.lon}&radius=${radius}`,
    headers: s ? auth(s) : {},
  });
  assert.equal(res.statusCode, 200, res.body);
  return res.json().alerts as Array<Record<string, any>>;
}

const reputation = async (s: Session) =>
  (await db.query('SELECT reputation FROM users WHERE id = $1', [s.id])).rows[0].reputation as number;

/** Cada test usa una zona distinta para no interferir con los demás. */
let zone = 0;
const place = () => ({ lat: 41 + ++zone * 0.5, lon: -3.7038 });

test('registro, perfil, refresco de un solo uso y cierre de sesión', async () => {
  const s = await user();
  const me = await app.inject({ method: 'GET', url: '/v1/me', headers: auth(s) });
  assert.equal(me.statusCode, 200);
  assert.equal(me.json().reputation, 0);

  const refreshed = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: s.refresh } });
  assert.equal(refreshed.statusCode, 200);
  const reuse = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: s.refresh } });
  assert.equal(reuse.statusCode, 401, 'un refresh token no se puede reutilizar');

  const next = refreshed.json().refreshToken;
  const out = await app.inject({ method: 'POST', url: '/v1/auth/logout', payload: { refreshToken: next } });
  assert.equal(out.statusCode, 204);
  const afterLogout = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: next } });
  assert.equal(afterLogout.statusCode, 401);
});

test('validación de registro e inicio de sesión', async () => {
  const short = await app.inject({
    method: 'POST',
    url: '/v1/auth/register',
    payload: { email: 'a@nex.test', password: 'corta', displayName: 'Ana' },
  });
  assert.equal(short.statusCode, 400);

  const s = await user();
  const email = (await db.query('SELECT email FROM users WHERE id = $1', [s.id])).rows[0].email;
  const dup = await app.inject({
    method: 'POST',
    url: '/v1/auth/register',
    payload: { email: email.toUpperCase(), password: 'contraseña-larga-1', displayName: 'Otro' },
  });
  assert.equal(dup.statusCode, 409, 'el correo es único sin distinguir mayúsculas');

  const bad = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email, password: 'incorrecta-123' } });
  assert.equal(bad.statusCode, 401);
  const good = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email, password: 'contraseña-larga-1' } });
  assert.equal(good.statusCode, 200);

  const anon = await app.inject({ method: 'GET', url: '/v1/me' });
  assert.equal(anon.statusCode, 401);
});

test('un aviso se ve cerca, no lejos, y sin sesión', async () => {
  const at = place();
  const a = await user();
  const res = await report(a, 'accident', at);
  assert.equal(res.statusCode, 201, res.body);
  assert.equal(res.json().alert.level, 'medium');
  assert.equal(res.json().alert.mine, true);

  const near = await list(null, { lat: at.lat + 0.01, lon: at.lon });
  assert.equal(near.length, 1);
  assert.equal(near[0]!.mine, false);
  assert.equal((await list(null, { lat: at.lat + 0.2, lon: at.lon })).length, 0);
});

test('las confirmaciones suben la confianza, prolongan la caducidad y dan reputación al autor', async () => {
  const at = place();
  const [a, b, c] = [await user(), await user(), await user()];
  const created = (await report(a, 'road_object', at)).json().alert;

  const v1 = await vote(b, created.id, 'confirm', at);
  assert.equal(v1.statusCode, 200, v1.body);
  assert.equal(v1.json().alert.confirmations, 1);
  assert.ok(v1.json().alert.confidence > created.confidence);
  assert.ok(new Date(v1.json().alert.expiresAt) >= new Date(created.expiresAt));

  const again = await vote(b, created.id, 'confirm', at);
  assert.equal(again.json().alert.confirmations, 1, 'votar dos veces no suma');

  const v2 = await vote(c, created.id, 'confirm', at);
  assert.equal(v2.json().alert.confirmations, 2);
  assert.equal(await reputation(a), 4);

  const seen = (await list(b, at))[0]!;
  assert.equal(seen.myVote, 'confirm');
});

test('un reporte duplicado cuenta como confirmación', async () => {
  const at = place();
  const [a, b] = [await user(), await user()];
  const first = (await report(a, 'accident', at)).json().alert;
  const dup = await report(b, 'accident', { lat: at.lat + 0.0005, lon: at.lon });
  assert.equal(dup.statusCode, 200);
  assert.equal(dup.json().merged, true);
  assert.equal(dup.json().alert.id, first.id);
  assert.equal(dup.json().alert.confirmations, 1);

  const other = await report(b, 'roadworks', at);
  assert.equal(other.statusCode, 201, 'otro tipo en el mismo sitio es un aviso distinto');
});

test('las negativas retiran el aviso y ajustan reputaciones', async () => {
  const at = place();
  const [a, b, c] = [await user(), await user(), await user()];
  const id = (await report(a, 'police', at)).json().alert.id;

  const d1 = await vote(b, id, 'deny', at);
  assert.equal(d1.json().removed, false, 'una sola negativa de peso normal no basta');
  assert.equal(d1.json().alert, null, 'pero deja la confianza a cero y el aviso deja de mostrarse');
  const d2 = await vote(c, id, 'deny', at);
  assert.equal(d2.json().removed, true);

  assert.equal((await list(a, at)).length, 0);
  assert.equal(await reputation(a), -5);
  assert.equal(await reputation(b), 1);
  const gone = await vote(await user(), id, 'confirm', at);
  assert.equal(gone.statusCode, 404);
});

test('no se puede votar el aviso propio ni desde lejos', async () => {
  const at = place();
  const [a, b] = [await user(), await user()];
  const id = (await report(a, 'hazard', at)).json().alert.id;
  assert.equal((await vote(a, id, 'confirm', at)).statusCode, 409);
  assert.equal((await vote(b, id, 'confirm', { lat: at.lat + 0.1, lon: at.lon })).statusCode, 422);
  const far = await report(b, 'hazard', at, { reporterLat: at.lat + 0.1 });
  assert.equal(far.statusCode, 422);
});

test('cuentas nuevas pesan poco y cuentas con mala reputación no cuentan', async () => {
  const at = place();
  const novice = await user({ fresh: true });
  const res = await report(novice, 'stopped_vehicle', at);
  assert.equal(res.json().alert.level, 'low');
  assert.equal((await list(null, at)).length, 1, 'se muestra, pero como poco fiable');

  const at2 = place();
  const troll = await user({ reputation: -30 });
  const hidden = await report(troll, 'accident', at2);
  assert.equal(hidden.statusCode, 201);
  assert.equal((await list(null, at2)).length, 0, 'nadie más lo ve');
  assert.equal((await list(troll, at2)).length, 1, 'su autor sí');
});

test('política legal: zona aproximada en ES y bloqueo en CH', async () => {
  const at = place();
  const a = await user();
  const res = await report(a, 'police', at, { heading: 90 });
  const alert = res.json().alert;
  assert.equal(alert.approximate, true);
  assert.equal(alert.zoneRadiusM, 1000);
  assert.equal(alert.heading, null);
  assert.notEqual(alert.lat, at.lat);

  const camera = (await report(a, 'speed_camera', at)).json().alert;
  assert.equal(camera.approximate, false);
  assert.equal(camera.lat, at.lat);

  const blocked = await report(a, 'police', place(), { country: 'CH' });
  assert.equal(blocked.statusCode, 451);
});

test('los avisos caducados no se devuelven y los oficiales no admiten votos', async () => {
  const at = place();
  const a = await user();
  const id = (await report(a, 'traffic_jam', at)).json().alert.id;
  await db.query(`UPDATE alerts SET expires_at = now() - interval '1 minute' WHERE id = $1`, [id]);
  assert.equal((await list(null, at)).length, 0);

  const at2 = place();
  const official = await db.query(
    `INSERT INTO alerts (type, lat, lon, country, source) VALUES ('speed_camera', $1, $2, 'ES', 'official') RETURNING id`,
    [at2.lat, at2.lon],
  );
  const seen = (await list(null, at2))[0]!;
  assert.equal(seen.confidence, 1);
  assert.equal(seen.expiresAt, null);
  assert.equal((await vote(a, official.rows[0].id, 'deny', at2)).statusCode, 409);
});

test('límite de reportes por usuario', async () => {
  const a = await user();
  for (let i = 0; i < 10; i++) {
    const res = await report(a, 'hazard', place());
    assert.equal(res.statusCode, 201, res.body);
  }
  assert.equal((await report(a, 'hazard', place())).statusCode, 429);
});

test('borrado de cuenta: exige contraseña y conserva los avisos de forma anónima', async () => {
  const at = place();
  const a = await user();
  await report(a, 'roadworks', at);
  const wrong = await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(a), payload: { password: 'no-es-esta-123' } });
  assert.equal(wrong.statusCode, 403);
  const ok = await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(a), payload: { password: 'contraseña-larga-1' } });
  assert.equal(ok.statusCode, 204);
  assert.equal((await app.inject({ method: 'GET', url: '/v1/me', headers: auth(a) })).statusCode, 401);
  assert.equal((await list(null, at)).length, 1);
});

test('peticiones mal formadas', async () => {
  const a = await user();
  assert.equal((await app.inject({ method: 'GET', url: '/v1/alerts?lat=200&lon=0' })).statusCode, 400);
  assert.equal((await report(a, 'ovni')).statusCode, 400);
  assert.equal((await vote(a, 'no-es-uuid', 'confirm')).statusCode, 400);
  assert.equal((await app.inject({ method: 'GET', url: '/v1/nada' })).statusCode, 404);
});
