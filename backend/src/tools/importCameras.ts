/**
 * Importa radares fijos desde un CSV de una fuente oficial (p. ej. datos abiertos de la DGT).
 *
 *   npm run import:cameras -- radares.csv ES
 *
 * Formato: una fila por radar, columnas `lat,lon[,heading]`, con o sin cabecera.
 * NEX no incluye ningún conjunto de datos: hay que obtenerlo y comprobar su licencia.
 */
import { readFile } from 'node:fs/promises';
import { config } from '../config.js';
import { createPool, withTx } from '../db.js';
import { boundingBox, sqlDistance } from '../geo.js';

const [file, country] = process.argv.slice(2);
if (!file || !country || country.length !== 2) {
  console.error('Uso: npm run import:cameras -- <archivo.csv> <país ISO de 2 letras>');
  process.exit(1);
}

const rows = (await readFile(file, 'utf8'))
  .split(/\r?\n/)
  .map((line) => line.split(/[,;]/).map((cell) => Number(cell.trim())))
  .filter((c) => Number.isFinite(c[0]) && Number.isFinite(c[1]) && Math.abs(c[0]!) <= 90 && Math.abs(c[1]!) <= 180);

const db = createPool(config.databaseUrl);
let inserted = 0;
await withTx(db, async (tx) => {
  for (const [lat, lon, heading] of rows) {
    const box = boundingBox(lat!, lon!, 50);
    const dup = await tx.query(
      `SELECT 1 FROM alerts WHERE type = 'speed_camera' AND source = 'official' AND removed_at IS NULL
          AND lat BETWEEN $3 AND $4 AND lon BETWEEN $5 AND $6 AND ${sqlDistance('$1', '$2')} <= 50 LIMIT 1`,
      [lat, lon, box.minLat, box.maxLat, box.minLon, box.maxLon],
    );
    if (dup.rows[0]) continue;
    await tx.query(
      `INSERT INTO alerts (type, lat, lon, heading, country, source) VALUES ('speed_camera', $1, $2, $3, $4, 'official')`,
      [lat, lon, Number.isFinite(heading) ? heading : null, country.toUpperCase()],
    );
    inserted++;
  }
});
console.log(`Filas válidas: ${rows.length}. Radares nuevos: ${inserted}.`);
await db.end();
