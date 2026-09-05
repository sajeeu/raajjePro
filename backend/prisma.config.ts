import 'dotenv/config';
import { defineConfig } from 'prisma/config';

// `prisma generate` runs from `npm install` (postinstall), before a .env may
// exist, and needs no database — so a missing URL must not stop it. Anything
// that does connect (migrate, studio) gets this deliberately unreachable
// placeholder and fails at the first connection with the placeholder's host in
// the message, which points straight at .env.example.
const databaseUrl =
  process.env.DATABASE_URL ?? 'postgresql://unset@database-url-not-set.invalid:5432/raajjepro';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  datasource: {
    url: databaseUrl,
  },
});
