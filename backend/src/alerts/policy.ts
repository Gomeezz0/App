import type { AlertType } from './types.js';

/**
 * Política legal por país para avisos de controles y radares.
 *
 *  - exact:    se muestra la ubicación reportada.
 *  - zone:     se muestra una zona aproximada (≈1 km), sin rumbo.
 *  - disabled: no se aceptan ni se muestran.
 *
 * AVISO: valores iniciales conservadores basados en información pública, no en
 * asesoramiento jurídico. Deben revisarse con un abogado en cada país antes de publicar.
 */
export type PolicyMode = 'exact' | 'zone' | 'disabled';

const REGULATED: ReadonlySet<AlertType> = new Set<AlertType>(['police', 'speed_camera']);

const DEFAULT_MODE: PolicyMode = 'zone';

const BY_COUNTRY: Record<string, Partial<Record<AlertType, PolicyMode>>> = {
  // España: los radares fijos son información pública de la DGT. Los controles se muestran
  // como zona, anticipando la reforma en preparación.
  ES: { speed_camera: 'exact', police: 'zone' },
  FR: { speed_camera: 'zone', police: 'zone' },
  CH: { speed_camera: 'disabled', police: 'disabled' },
  DE: { speed_camera: 'disabled', police: 'disabled' },
};

export function policyFor(country: string | null | undefined, type: AlertType): PolicyMode {
  if (!REGULATED.has(type)) return 'exact';
  const entry = country ? BY_COUNTRY[country.toUpperCase()] : undefined;
  return entry?.[type] ?? DEFAULT_MODE;
}

export const ZONE_RADIUS_M = 1_000;
const GRID_DEG = 0.01;

/** Centro de la celda de ~1 km que contiene el punto. */
export function coarsen(lat: number, lon: number): { lat: number; lon: number } {
  const snap = (v: number) => Number(((Math.floor(v / GRID_DEG) + 0.5) * GRID_DEG).toFixed(5));
  return { lat: snap(lat), lon: snap(lon) };
}
