import { defineConfig } from 'vitest/config';

/**
 * Why this file exists: the jsdom panel suites.
 *
 * `packages/admin/index.html` is one 400 KB file containing the whole back
 * office, and the only honest way to test a panel view is to boot it — parse
 * it, run its scripts, click a row, read what a browser would draw. That costs
 * well over a second per boot even when nothing is wrong.
 *
 * Vitest's default 5000 ms is a per-test budget, but the clock is wall time and
 * several of those boots run CONCURRENTLY in the worker pool. On a cold cache
 * the pool was starving them past the default and two suites failed with
 * «Test timed out in 5000ms» — both of which passed in 1.7 s in isolation and
 * both of which passed on the warm rerun. A flake that only appears on a cold
 * CI runner is worse than a slow suite: it teaches everybody to re-run red.
 *
 * So the budget is raised to something a loaded pool cannot cross by accident,
 * while still being far below "this test has hung". It is NOT a licence to
 * write slow tests: the mother-card render suite boots once per fixture rather
 * than once per assertion, and any new panel suite should do the same.
 */
export default defineConfig({
  test: {
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
