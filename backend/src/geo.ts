const EARTH_RADIUS_M = 6_371_000;
const rad = (deg: number) => (deg * Math.PI) / 180;

export function haversineMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Caja que contiene el círculo dado. No trata el antimeridiano (±180°). */
export function boundingBox(lat: number, lon: number, radiusM: number) {
  const dLat = radiusM / 111_320;
  const dLon = radiusM / (111_320 * Math.max(0.01, Math.cos(rad(lat))));
  return { minLat: lat - dLat, maxLat: lat + dLat, minLon: lon - dLon, maxLon: lon + dLon };
}

/** Expresión SQL de distancia en metros entre (lat, lon) de la fila y los parámetros indicados. */
export function sqlDistance(latParam: string, lonParam: string): string {
  return `(2 * ${EARTH_RADIUS_M} * asin(least(1, sqrt(
    power(sin(radians(lat - ${latParam}) / 2), 2) +
    cos(radians(${latParam})) * cos(radians(lat)) * power(sin(radians(lon - ${lonParam}) / 2), 2)))))`;
}
