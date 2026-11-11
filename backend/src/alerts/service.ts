import { withTx, type Db, type Tx } from '../db.js';
import { HttpError } from '../errors.js';
import { boundingBox, haversineMeters, sqlDistance } from '../geo.js';
import { coarsen, policyFor, ZONE_RADIUS_M } from './policy.js';
import {
  confidence,
  extendedExpiry,
  level,
  MIN_REPUTATION,
  REPUTATION,
  shouldRemove,
  userWeight,
  type Tally,
} from './trust.js';
import {
  MAX_REPORT_DISTANCE_M,
  MAX_VOTE_DISTANCE_M,
  REPORT_WINDOW_MINUTES,
  REPORTS_PER_WINDOW,
  TYPE_RULES,
  type AlertType,
} from './types.js';

export interface AlertView {
  id: string;
  type: AlertType;
  lat: number;
  lon: number;
  heading: number | null;
  /** true cuando la ubicación es una zona aproximada por política legal. */
  approximate: boolean;
  zoneRadiusM: number | null;
  source: 'community' | 'official';
  confidence: number;
  level: 'low' | 'medium' | 'high';
  confirmations: number;
  denials: number;
  createdAt: string;
  expiresAt: string | null;
  mine: boolean;
  myVote: 'confirm' | 'deny' | null;
}

const ACTIVE = 'a.removed_at IS NULL AND (a.expires_at IS NULL OR a.expires_at > now())';

/** Selección de un aviso con el recuento de votos. $1 es siempre el usuario que consulta (o NULL). */
const SELECT = `
  SELECT a.*, coalesce(v.confirm_weight, 0) AS confirm_weight, coalesce(v.deny_weight, 0) AS deny_weight,
         coalesce(v.confirm_count, 0) AS confirm_count, coalesce(v.deny_count, 0) AS deny_count,
         (SELECT vote FROM alert_votes mv WHERE mv.alert_id = a.id AND mv.user_id = $1::uuid) AS my_vote
    FROM alerts a
    LEFT JOIN LATERAL (
      SELECT sum(weight) FILTER (WHERE vote = 'confirm') AS confirm_weight,
             sum(weight) FILTER (WHERE vote = 'deny') AS deny_weight,
             count(*) FILTER (WHERE vote = 'confirm')::int AS confirm_count,
             count(*) FILTER (WHERE vote = 'deny')::int AS deny_count
        FROM alert_votes WHERE alert_id = a.id
    ) v ON true`;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Row = Record<string, any>;

function tallyOf(row: Row): Tally {
  return {
    reporterWeight: Number(row.reporter_weight),
    confirmWeight: Number(row.confirm_weight),
    denyWeight: Number(row.deny_weight),
  };
}

/** Aplica la política legal y el motor de confianza. Devuelve null si el aviso no debe mostrarse. */
function present(row: Row, userId: string | null): AlertView | null {
  const type = row.type as AlertType;
  const mode = policyFor(row.country, type);
  if (mode === 'disabled') return null;

  const mine = userId !== null && row.reporter_id === userId;
  const official = row.source === 'official';
  const conf = official ? 1 : confidence(tallyOf(row));
  // Los avisos sin ningún respaldo (autor con cuenta limitada) solo los ve su autor.
  if (conf === 0 && !mine) return null;

  const zone = mode === 'zone';
  const position = zone ? coarsen(row.lat, row.lon) : { lat: row.lat as number, lon: row.lon as number };
  return {
    id: row.id,
    type,
    ...position,
    heading: zone ? null : row.heading,
    approximate: zone,
    zoneRadiusM: zone ? ZONE_RADIUS_M : null,
    source: row.source,
    confidence: Number(conf.toFixed(3)),
    level: level(conf),
    confirmations: row.confirm_count,
    denials: row.deny_count,
    createdAt: row.created_at.toISOString(),
    expiresAt: row.expires_at ? row.expires_at.toISOString() : null,
    mine,
    myVote: row.my_vote ?? null,
  };
}

export async function listAlerts(
  db: Db,
  q: { lat: number; lon: number; radiusM: number; userId: string | null },
): Promise<AlertView[]> {
  const box = boundingBox(q.lat, q.lon, q.radiusM);
  const dist = sqlDistance('$2', '$3');
  const { rows } = await db.query(
    `${SELECT}
      WHERE ${ACTIVE}
        AND a.lat BETWEEN $5 AND $6 AND a.lon BETWEEN $7 AND $8
        AND ${dist} <= $4
      ORDER BY ${dist}
      LIMIT 300`,
    [q.userId, q.lat, q.lon, q.radiusM, box.minLat, box.maxLat, box.minLon, box.maxLon],
  );
  return rows.map((r) => present(r, q.userId)).filter((a): a is AlertView => a !== null);
}

async function loadForUpdate(tx: Tx, alertId: string, userId: string): Promise<Row | null> {
  // El bloqueo va en una consulta aparte: FOR UPDATE no admite el LEFT JOIN LATERAL con agregados.
  const locked = await tx.query(`SELECT id FROM alerts a WHERE a.id = $1 AND ${ACTIVE} FOR UPDATE`, [alertId]);
  if (!locked.rows[0]) return null;
  const { rows } = await tx.query(`${SELECT} WHERE a.id = $2`, [userId, alertId]);
  return rows[0] ?? null;
}

async function weightOf(tx: Tx, userId: string): Promise<number> {
  const { rows } = await tx.query(
    'SELECT reputation, extract(epoch FROM now() - created_at) / 3600 AS age_hours FROM users WHERE id = $1',
    [userId],
  );
  if (!rows[0]) throw new HttpError(401, 'unauthorized', 'La cuenta ya no existe');
  return userWeight(rows[0].reputation, Number(rows[0].age_hours));
}

async function addReputation(tx: Tx, userIds: string[], delta: number): Promise<void> {
  if (userIds.length === 0 || delta === 0) return;
  await tx.query('UPDATE users SET reputation = greatest($3, reputation + $2) WHERE id = ANY($1::uuid[])', [
    userIds,
    delta,
    MIN_REPUTATION,
  ]);
}

export interface VoteResult {
  alert: AlertView | null;
  /** true si el aviso se ha retirado a raíz de este voto. */
  removed: boolean;
}

async function castVote(tx: Tx, row: Row, userId: string, vote: 'confirm' | 'deny'): Promise<VoteResult> {
  if (row.my_vote === vote) return { alert: present(row, userId), removed: false };

  const weight = await weightOf(tx, userId);
  await tx.query(
    `INSERT INTO alert_votes (alert_id, user_id, vote, weight) VALUES ($1, $2, $3, $4)
     ON CONFLICT (alert_id, user_id) DO UPDATE SET vote = excluded.vote, weight = excluded.weight, created_at = now()`,
    [row.id, userId, vote, weight],
  );
  const fresh = (await tx.query(`${SELECT} WHERE a.id = $2`, [userId, row.id])).rows[0]!;
  const tally = tallyOf(fresh);
  const type = fresh.type as AlertType;

  if (vote === 'confirm') {
    // Solo la primera vez que alguien confirma (no al cambiar de voto) y con tope por aviso.
    const firstTime = row.my_vote === null;
    if (firstTime && weight > 0 && fresh.reporter_id && fresh.confirm_count <= REPUTATION.maxRewardedConfirmations) {
      await addReputation(tx, [fresh.reporter_id], REPUTATION.reportConfirmed);
    }
    if (fresh.expires_at) {
      const rules = TYPE_RULES[type];
      const expiry = extendedExpiry(new Date(), fresh.created_at, fresh.expires_at, rules.ttlMinutes, rules.maxLifeMinutes);
      await tx.query('UPDATE alerts SET expires_at = $2 WHERE id = $1', [fresh.id, expiry]);
      fresh.expires_at = expiry;
    }
  }

  if (shouldRemove(tally)) {
    await tx.query(`UPDATE alerts SET removed_at = now(), removed_reason = 'denied' WHERE id = $1`, [fresh.id]);
    const deniers = await tx.query(`SELECT user_id FROM alert_votes WHERE alert_id = $1 AND vote = 'deny' AND weight > 0`, [
      fresh.id,
    ]);
    await addReputation(
      tx,
      deniers.rows.map((r) => r.user_id as string),
      REPUTATION.denyUpheld,
    );
    if (fresh.reporter_id && fresh.confirm_count === 0) {
      await addReputation(tx, [fresh.reporter_id], REPUTATION.reportRejected);
    }
    return { alert: null, removed: true };
  }
  return { alert: present(fresh, userId), removed: false };
}

export interface ReportInput {
  type: AlertType;
  lat: number;
  lon: number;
  heading?: number | undefined;
  country?: string | undefined;
  reporterLat: number;
  reporterLon: number;
}

export interface ReportResult {
  alert: AlertView;
  /** true si ya existía un aviso equivalente y el reporte se ha contado como confirmación. */
  merged: boolean;
}

export async function reportAlert(db: Db, userId: string, input: ReportInput): Promise<ReportResult> {
  if (policyFor(input.country, input.type) === 'disabled') {
    throw new HttpError(451, 'not_available_in_region', 'Este tipo de aviso no está disponible en este país');
  }
  if (haversineMeters(input.lat, input.lon, input.reporterLat, input.reporterLon) > MAX_REPORT_DISTANCE_M) {
    throw new HttpError(422, 'too_far', 'Solo puedes avisar de incidencias cercanas a tu posición');
  }

  return withTx(db, async (tx) => {
    const recent = await tx.query(
      `SELECT count(*)::int AS n FROM alerts
        WHERE reporter_id = $1 AND created_at > now() - make_interval(mins => $2)`,
      [userId, REPORT_WINDOW_MINUTES],
    );
    if (recent.rows[0].n >= REPORTS_PER_WINDOW) {
      throw new HttpError(429, 'too_many_reports', 'Has enviado demasiados avisos. Inténtalo más tarde');
    }

    const rules = TYPE_RULES[input.type];
    const box = boundingBox(input.lat, input.lon, rules.mergeRadiusM);
    const dist = sqlDistance('$2', '$3');
    const nearby = await tx.query(
      `SELECT a.id FROM alerts a
        WHERE ${ACTIVE} AND a.type = $1
          AND a.lat BETWEEN $5 AND $6 AND a.lon BETWEEN $7 AND $8 AND ${dist} <= $4
        ORDER BY ${dist} LIMIT 1`,
      [input.type, input.lat, input.lon, rules.mergeRadiusM, box.minLat, box.maxLat, box.minLon, box.maxLon],
    );

    if (nearby.rows[0]) {
      const existing = await loadForUpdate(tx, nearby.rows[0].id, userId);
      if (existing) {
        const own = existing.reporter_id === userId;
        const voteable = !own && existing.source === 'community' && existing.my_vote === null;
        const result = voteable ? await castVote(tx, existing, userId, 'confirm') : null;
        const view = result?.alert ?? present(existing, userId);
        if (view) return { alert: view, merged: true };
      }
    }

    const weight = await weightOf(tx, userId);
    const inserted = await tx.query(
      `INSERT INTO alerts (type, lat, lon, heading, country, reporter_id, reporter_weight, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, now() + make_interval(mins => $8)) RETURNING id`,
      [input.type, input.lat, input.lon, input.heading ?? null, input.country?.toUpperCase() ?? null, userId, weight, rules.ttlMinutes],
    );
    const row = (await tx.query(`${SELECT} WHERE a.id = $2`, [userId, inserted.rows[0].id])).rows[0]!;
    return { alert: present(row, userId)!, merged: false };
  });
}

export async function voteOnAlert(
  db: Db,
  userId: string,
  alertId: string,
  input: { vote: 'confirm' | 'deny'; lat: number; lon: number },
): Promise<VoteResult> {
  return withTx(db, async (tx) => {
    const row = await loadForUpdate(tx, alertId, userId);
    if (!row || policyFor(row.country, row.type) === 'disabled') {
      throw new HttpError(404, 'not_found', 'El aviso ya no existe');
    }
    if (row.reporter_id === userId) throw new HttpError(409, 'own_alert', 'No puedes votar tu propio aviso');
    if (row.source === 'official') throw new HttpError(409, 'official_alert', 'Los datos oficiales no admiten votos');
    if (haversineMeters(row.lat, row.lon, input.lat, input.lon) > MAX_VOTE_DISTANCE_M) {
      throw new HttpError(422, 'too_far', 'Tienes que estar cerca del aviso para valorarlo');
    }
    return castVote(tx, row, userId, input.vote);
  });
}

/** Borra definitivamente avisos caducados o retirados hace más de una semana. */
export async function purgeOldAlerts(db: Db): Promise<number> {
  const { rowCount } = await db.query(
    `DELETE FROM alerts
      WHERE coalesce(removed_at, expires_at) < now() - interval '7 days'`,
  );
  return rowCount ?? 0;
}
