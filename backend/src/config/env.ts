/**
 * Environment access.
 *
 * Configuration comes from process environment variables and nowhere else —
 * see .env.example for the strategy. Locally the values arrive via
 * `node --env-file=.env`; in CI and deployed environments the host injects
 * them. Nothing in src/ reads a file.
 *
 * Phase 2 replaces call sites of this helper with the typed config module that
 * validates every variable at startup. Until then, a missing variable fails at
 * first use with a message naming it.
 */
export function requireEnv(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === '') {
    throw new Error(`Missing required environment variable ${name} (see .env.example)`);
  }
  return value;
}
