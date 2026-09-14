import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts', 'src/**/*.test.ts'],
    // Empties the test database once per run — see the file for why that is
    // a *per-run* job and not a per-test one.
    globalSetup: ['test/global-setup.ts'],
    setupFiles: ['test/setup.ts'],
    // Database-backed tests share one connection pool; keep them in one worker.
    fileParallelism: false,
  },
});
