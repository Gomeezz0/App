/**
 * Motor de confianza de avisos comunitarios. Funciones puras: sin base de datos ni reloj.
 *
 * Idea: un aviso vale lo que valen quienes lo respaldan. Cada usuario aporta un peso
 * según su reputación; las negativas ("ya no está") pesan más que las confirmaciones
 * porque retirar tarde un aviso falso es peor que retirar pronto uno cierto.
 */

export const SHADOW_LIMIT_REPUTATION = -20;
export const MIN_REPUTATION = -50;
export const NEW_ACCOUNT_HOURS = 24;
const DENY_FACTOR = 1.5;

/** Peso del voto o reporte de un usuario. 0 = no cuenta (cuenta limitada por mala reputación). */
export function userWeight(reputation: number, accountAgeHours: number): number {
  if (reputation <= SHADOW_LIMIT_REPUTATION) return 0;
  if (accountAgeHours < NEW_ACCOUNT_HOURS) return 0.3;
  return Math.min(1.5, Math.max(0.3, 1 + reputation / 100));
}

export interface Tally {
  reporterWeight: number;
  confirmWeight: number;
  denyWeight: number;
}

export function score(t: Tally): number {
  return t.reporterWeight + t.confirmWeight - DENY_FACTOR * t.denyWeight;
}

/** Confianza en [0, 1). Crece rápido con las primeras confirmaciones y se satura. */
export function confidence(t: Tally): number {
  const s = score(t);
  return s <= 0 ? 0 : 1 - Math.exp(-s / 1.5);
}

export type ConfidenceLevel = 'low' | 'medium' | 'high';

export function level(conf: number): ConfidenceLevel {
  if (conf >= 0.75) return 'high';
  if (conf >= 0.35) return 'medium';
  return 'low';
}

/** Un aviso se retira cuando las negativas son suficientes en absoluto y frente a los apoyos. */
export function shouldRemove(t: Tally): boolean {
  return t.denyWeight >= 1.5 && t.denyWeight >= 0.6 * (t.reporterWeight + t.confirmWeight);
}

/** Nueva caducidad tras una confirmación: se prolonga medio TTL desde ahora, con tope de vida máxima. */
export function extendedExpiry(
  now: Date,
  createdAt: Date,
  currentExpiry: Date,
  ttlMinutes: number,
  maxLifeMinutes: number,
): Date {
  const candidate = now.getTime() + (ttlMinutes / 2) * 60_000;
  const cap = createdAt.getTime() + maxLifeMinutes * 60_000;
  return new Date(Math.max(currentExpiry.getTime(), Math.min(candidate, cap)));
}

export const REPUTATION = {
  /** Al autor, por cada confirmación ajena (hasta MAX_REWARDED_CONFIRMATIONS por aviso). */
  reportConfirmed: 2,
  maxRewardedConfirmations: 5,
  /** Al autor, si su aviso se retira por negativas sin ninguna confirmación. */
  reportRejected: -5,
  /** A quien desmintió un aviso que acabó retirado. */
  denyUpheld: 1,
} as const;
