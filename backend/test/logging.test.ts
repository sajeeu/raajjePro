import { Writable } from 'node:stream';

import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';

import { loggerOptionsForStream } from '../src/core/logging.js';
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
          tokens: { accessToken: 'eyJ-top', refreshToken: 'rt-secret' },
          newEmail: 'n@x.test',
          phoneE164: '+9607771234',
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
    expect(output).not.toContain('eyJ-top');
    expect(output).not.toContain('rt-secret');
    expect(output).not.toContain('n@x.test');
    expect(output).not.toContain('+9607771234');
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
