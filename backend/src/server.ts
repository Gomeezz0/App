import { purgeOldAlerts } from './alerts/service.js';
import { buildApp } from './app.js';
import { config } from './config.js';
import { createPool, migrate } from './db.js';

const db = createPool(config.databaseUrl);
await migrate(db);
const app = await buildApp(db, { logger: true });

const purge = setInterval(() => {
  purgeOldAlerts(db).catch((err) => app.log.error(err));
}, 60 * 60 * 1000);
purge.unref();

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, async () => {
    await app.close();
    await db.end();
    process.exit(0);
  });
}

await app.listen({ port: config.port, host: config.host });
