/**
 * Backend entrypoint: validate configuration, connect, build the app, listen.
 * A configuration error prints every issue and exits 1 before the database is
 * touched. SIGTERM/SIGINT close the server and the connection pool.
 */
import { buildApp } from './app.js';
import type { Config } from './config/env.js';
import { ConfigError, loadConfig } from './config/env.js';
import { systemClock } from './core/clock.js';
import { createPrismaClient } from './db/client.js';

let config: Config;
try {
  config = loadConfig(process.env);
} catch (error) {
  if (error instanceof ConfigError) {
    console.error(error.message);
    process.exit(1);
  }
  throw error;
}

const prisma = createPrismaClient(config.databaseUrl);
const app = await buildApp(config, { prisma, clock: systemClock });

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'shutting down');
  await app.close();
  await prisma.$disconnect();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));

await app.listen({ port: config.port, host: config.host });
