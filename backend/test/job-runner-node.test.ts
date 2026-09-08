import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { JobRunner } from '../src/jobs/runner.js';
import { controllableClock, databaseUrl } from './helpers/app.js';

const silent = { info: () => undefined, warn: () => undefined, error: () => undefined };

describe.skipIf(databaseUrl === undefined)('JobRunner (Node-side jobs)', () => {
  let prisma: PrismaClient;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('runOnce runs the job and upserts its heartbeat row with the clock time', async () => {
    const runner = new JobRunner({ prisma, clock: time.clock, log: silent });
    const name = `test-job-${Math.random().toString(36).slice(2)}`;
    let runs = 0;
    runner.register({
      name,
      everyMs: 60_000,
      run: () => {
        runs += 1;
        return Promise.resolve();
      },
    });
    await runner.runOnce(name);
    await runner.runOnce(name);
    expect(runs).toBe(2);
    const beat = await prisma.jobHeartbeat.findUniqueOrThrow({ where: { jobName: name } });
    expect(beat.firedAt.getTime()).toBe(time.clock().getTime());
  });

  it('a failing job is logged and does not write a heartbeat, and the runner survives it', async () => {
    const warned: string[] = [];
    const runner = new JobRunner({
      prisma,
      clock: time.clock,
      log: {
        ...silent,
        error: (_o, msg) => {
          warned.push(msg);
        },
      },
    });
    const name = `test-job-${Math.random().toString(36).slice(2)}`;
    runner.register({ name, everyMs: 60_000, run: () => Promise.reject(new Error('boom')) });
    await runner.runOnce(name);
    expect(warned).toContain('job failed');
    expect(await prisma.jobHeartbeat.findUnique({ where: { jobName: name } })).toBeNull();
  });

  it('two runners cannot run the same job at once — the advisory lock makes the second skip', async () => {
    const a = new JobRunner({ prisma, clock: time.clock, log: silent });
    const b = new JobRunner({ prisma, clock: time.clock, log: silent });
    const name = `test-job-${Math.random().toString(36).slice(2)}`;
    let concurrent = 0;
    let peak = 0;
    const job = {
      name,
      everyMs: 60_000,
      run: async () => {
        concurrent += 1;
        peak = Math.max(peak, concurrent);
        await new Promise((r) => setTimeout(r, 150));
        concurrent -= 1;
      },
    };
    a.register(job);
    b.register(job);
    const [ra, rb] = await Promise.all([a.runOnce(name), b.runOnce(name)]);
    expect(peak).toBe(1);
    expect([ra, rb].filter((r) => r === 'skipped')).toHaveLength(1);
  });

  it('start() schedules and stop() clears without leaking a timer', async () => {
    const runner = new JobRunner({ prisma, clock: time.clock, log: silent });
    let runs = 0;
    runner.register({
      name: `test-job-${Math.random().toString(36).slice(2)}`,
      everyMs: 20,
      run: () => {
        runs += 1;
        return Promise.resolve();
      },
    });
    runner.start();
    await new Promise((r) => setTimeout(r, 120));
    runner.stop();
    const after = runs;
    await new Promise((r) => setTimeout(r, 60));
    expect(runs).toBeGreaterThanOrEqual(2);
    expect(runs).toBe(after);
  });
});
