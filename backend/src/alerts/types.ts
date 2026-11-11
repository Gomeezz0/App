export const ALERT_TYPES = [
  'police',
  'speed_camera',
  'accident',
  'traffic_jam',
  'stopped_vehicle',
  'road_object',
  'roadworks',
  'road_closed',
  'weather',
  'hazard',
] as const;

export type AlertType = (typeof ALERT_TYPES)[number];

interface TypeRules {
  /** Vida inicial de un aviso comunitario. */
  ttlMinutes: number;
  /** Vida máxima aunque se siga confirmando. */
  maxLifeMinutes: number;
  /** Un reporte del mismo tipo a menos de esta distancia se trata como confirmación. */
  mergeRadiusM: number;
}

const HOUR = 60;
const DAY = 24 * HOUR;

export const TYPE_RULES: Record<AlertType, TypeRules> = {
  police: { ttlMinutes: 45, maxLifeMinutes: 3 * HOUR, mergeRadiusM: 300 },
  speed_camera: { ttlMinutes: 30 * DAY, maxLifeMinutes: 365 * DAY, mergeRadiusM: 150 },
  accident: { ttlMinutes: 60, maxLifeMinutes: 4 * HOUR, mergeRadiusM: 200 },
  traffic_jam: { ttlMinutes: 30, maxLifeMinutes: 3 * HOUR, mergeRadiusM: 500 },
  stopped_vehicle: { ttlMinutes: 45, maxLifeMinutes: 3 * HOUR, mergeRadiusM: 150 },
  road_object: { ttlMinutes: 45, maxLifeMinutes: 3 * HOUR, mergeRadiusM: 150 },
  roadworks: { ttlMinutes: DAY, maxLifeMinutes: 30 * DAY, mergeRadiusM: 200 },
  road_closed: { ttlMinutes: 6 * HOUR, maxLifeMinutes: 14 * DAY, mergeRadiusM: 200 },
  weather: { ttlMinutes: 2 * HOUR, maxLifeMinutes: 12 * HOUR, mergeRadiusM: 1000 },
  hazard: { ttlMinutes: 45, maxLifeMinutes: 3 * HOUR, mergeRadiusM: 150 },
};

/** Distancia máxima entre quien reporta y el punto reportado. */
export const MAX_REPORT_DISTANCE_M = 2_000;
/** Distancia máxima para confirmar o desmentir un aviso. */
export const MAX_VOTE_DISTANCE_M = 3_000;
/** Reportes permitidos por usuario en la ventana. */
export const REPORT_WINDOW_MINUTES = 10;
export const REPORTS_PER_WINDOW = 10;
