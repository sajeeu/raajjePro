import { Writable } from 'node:stream';

import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';

import type { Config } from '../src/config/env.js';
import { loggerOptions } from '../src/core/logging.js';
import { testConfig } from './helpers/app.js';

/** Collects every line pino writes so the test can assert on the raw log output. */
function captureStream() {
  const lines: string[] = [];
  const stream = new Writable({
    write(chunk: Buffer, _encoding, callback) {
      lines.push(chunk.toString('utf8'));
      callback();
    },
  });
  return { lines, stream };
}

/**
 * `loggerOptions` returns Fastify's own logger-option union, which also allows
 * a bare `boolean` — a case this function never produces, but one the type
 * checker must be shown isn't happening before the result can be spread.
 */
function loggerOptionsForStream(config: Config, stream: Writable) {
  const options = loggerOptions(config);
  if (typeof options === 'boolean') {
    throw new Error('unreachable: loggerOptions never returns a boolean');
  }
  return { ...options, stream };
}

describe('loggerOptions redaction', () => {
  it('redacts sensitive keys at the top level and nested, never bare values', async () => {
    const { lines, stream } = captureStream();
    // testConfig() forces LOG_LEVEL 'silent' so app tests stay quiet; this test needs
    // actual output to inspect, so it overrides just the level.
    const config = { ...testConfig(), logLevel: 'info' as const };
    const app = Fastify({ logger: loggerOptionsForStream(config, stream) });

    app.get('/probe', (request) => {
      request.log.info(
        {
          email: 'top@x.test',
          user: { email: 'nested@x.test', profile: { phone: '7771234' } },
          code: '123456',
        },
        'probe',
      );
      return { ok: true };
    });

    await app.ready();
    await app.inject({ method: 'GET', url: '/probe' });
    await app.close();

    const output = lines.join('\n');
    expect(output).not.toContain('top@x.test');
    expect(output).not.toContain('nested@x.test');
    expect(output).not.toContain('7771234');
    expect(output).not.toContain('123456');
    expect(output).toContain('[redacted]');
  });

  it('never logs a query string', async () => {
    const { lines, stream } = captureStream();
    const config = { ...testConfig(), logLevel: 'info' as const };
    const app = Fastify({ logger: loggerOptionsForStream(config, stream) });

    app.get('/v1/nowhere', () => ({ ok: true }));

    await app.ready();
    await app.inject({ method: 'GET', url: '/v1/nowhere?email=q@x.test' });
    await app.close();

    const output = lines.join('\n');
    expect(output).not.toContain('q@x.test');
  });
});
