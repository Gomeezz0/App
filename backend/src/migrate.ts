import { config } from './config.js';
import { createPool, migrate } from './db.js';

const db = createPool(config.databaseUrl);
const applied = await migrate(db);
console.log(applied.length ? `Migraciones aplicadas: ${applied.join(', ')}` : 'Sin migraciones pendientes');
await db.end();
