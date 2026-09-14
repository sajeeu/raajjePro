import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

import { loadConfig } from '../src/config/env.js';

/**
 * CI's environment can boot the application.
 *
 * This exists because it did not, for four days and six pushes, and nobody
 * saw it. §Phase 8 added `MEDIA_SIGNING_KEY` as a required key; the workflow
 * never learned about it, so every boot step since has died on `ConfigError`
 * — while `npm test` stayed green either side of it, because the test harness
 * supplies its own keys through `testConfig`. Locally nothing failed at all,
 * because `backend/.env` has the key. The one place the gap showed was a red
 * badge on GitHub that three sessions in a row pushed past.
 *
 * So the assertion belongs *here*, where people look, rather than only in the
 * workflow that was already failing. A phase that adds a required variable
 * now breaks a local test with a message naming it.
 *
 * The env block is read rather than duplicated, for the obvious reason: a
 * copy of CI's environment kept in a test would drift from CI's environment,
 * which is the failure this file is about.
 */

/**
 * The workflow's job-level `env:` block, read without a YAML parser.
 *
 * `yaml` is in `node_modules` only transitively, and `npm ci --dry-run` is one
 * of this repository's gates precisely because such things disappear on a
 * dependency bump. The block is flat `KEY: value` pairs, which is worth the
 * twelve lines to avoid taking a dependency on somebody else's dependency.
 */
function ciJobEnv(): Record<string, string> {
  const yaml = readFileSync(new URL('../../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const lines = yaml.split('\n');
  const start = lines.findIndex((line) => line === '    env:');
  expect(start, 'the workflow should carry a job-level env: block at four spaces').toBeGreaterThan(
    -1,
  );

  const env: Record<string, string> = {};
  for (const line of lines.slice(start + 1)) {
    if (line.trim() === '' || line.trimStart().startsWith('#')) continue;
    const match = /^ {6}([A-Z0-9_]+):\s*(.*)$/.exec(line);
    // The first line at any other indent ends the block. Destructured rather
    // than indexed because `noUncheckedIndexedAccess` types a capture group as
    // possibly undefined, and it is right to: a regex that matched says
    // nothing to the compiler about how many groups it filled.
    const [, key, value] = match ?? [];
    if (key === undefined || value === undefined) break;
    env[key] = value.trim();
  }
  return env;
}

describe('the CI workflow can boot the application', () => {
  it('sets every variable the config loader requires', () => {
    const env = ciJobEnv();
    // Contributed by the boot step rather than the job block, because it is
    // the only variable that is genuinely about that one step.
    const asCiBoots = { ...env, PORT: '3000' };

    // Throws a ConfigError listing exactly what is missing, which is the
    // message worth failing with.
    expect(() => loadConfig(asCiBoots)).not.toThrow();
  });

  it('gives the three signing keys three different values', () => {
    // env.ts refuses a shared key: a signature forged in one context would
    // otherwise be valid in another. Asserted separately from the load above
    // so a reader of a failure knows which rule bit.
    const env = ciJobEnv();
    const keys = [env.ADMIN_TOTP_ENCRYPTION_KEY, env.AUTH_JWT_SECRET, env.MEDIA_SIGNING_KEY].filter(
      (value) => value !== undefined,
    );
    expect(keys).toHaveLength(3);
    expect(new Set(keys).size).toBe(3);
  });
});
