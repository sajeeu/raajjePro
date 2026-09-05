import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts', 'src/**/*.test.ts'],
    setupFiles: ['test/setup.ts'],
    // Database-backed tests share one connection pool; keep them in one worker.
    fileParallelism: false,
  },
});
