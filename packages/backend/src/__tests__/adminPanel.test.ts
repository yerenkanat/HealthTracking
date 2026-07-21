/**
 * Checks the admin panel's single HTML file for the failures a one-file,
 * build-step-free page is prone to.
 *
 * There is no compiler between this file and a staff member's browser: a
 * renamed element id, or a chart still reading an element that was deleted,
 * fails silently at runtime as an empty card. That happened while the overview
 * was being rebuilt — #spark was removed and three call sites still referenced
 * it — which is what prompted this.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const html = readFileSync(
  fileURLToPath(new URL('../../../admin/index.html', import.meta.url)),
  'utf8',
);

/** ids the markup defines. */
function definedIds(): Set<string> {
  const out = new Set<string>();
  for (const m of html.matchAll(/\bid="([A-Za-z][\w-]*)"/g)) out.add(m[1]);
  return out;
}

/** ids the script looks up. */
function referencedIds(): Array<{ id: string; how: string }> {
  const out: Array<{ id: string; how: string }> = [];
  for (const m of html.matchAll(/\$\("#([A-Za-z][\w-]*)"\)/g)) out.push({ id: m[1], how: '$("#…")' });
  for (const m of html.matchAll(/getElementById\("([A-Za-z][\w-]*)"\)/g)) {
    out.push({ id: m[1], how: 'getElementById' });
  }
  return out;
}

describe('admin panel markup and script agree', () => {
  it('every element the script looks up exists in the markup', () => {
    const defined = definedIds();
    const missing = referencedIds()
      .filter((r) => !defined.has(r.id))
      .map((r) => `${r.how} #${r.id}`);
    expect([...new Set(missing)], `script reads elements that do not exist: ${missing.join(', ')}`).toEqual([]);
  });

  it('the extraction found something to check', () => {
    // Without this, a regex that stopped matching would make the test above
    // pass while checking nothing.
    expect(definedIds().size).toBeGreaterThan(20);
    expect(referencedIds().length).toBeGreaterThan(20);
  });

  it('the overview renders the product metrics it fetches', () => {
    expect(html).toContain('/admin/bi');
    for (const id of ['kpis', 'biTrend', 'biRetention', 'biEngagement']) {
      expect(definedIds().has(id), `overview should contain #${id}`).toBe(true);
    }
  });

  it('does not present invented numbers as measurements', () => {
    // The KPI row shipped '+4.2% this week' and '2 unresolved' as string
    // literals beside real counts, and the "Alerts · last 7 days" chart drew
    // two hardcoded arrays — in live mode as well as demo. On a metrics screen
    // a made-up number is worse than a missing one, because it gets acted on.
    const overview = html.slice(html.indexOf('function renderKpis'), html.indexOf('function renderRetention'));
    expect(overview).not.toMatch(/\+\d+(\.\d+)?%\s*<\/b>\s*this week/);
    expect(overview).not.toMatch(/\d+ unresolved/);
    // A literal array of small integers inside the trend drawing code is the
    // shape the fake series took.
    const chart = html.slice(html.indexOf('function drawBiTrend'), html.indexOf('function drawBiTrend') + 3000);
    expect(chart).not.toMatch(/=\s*\[\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*\d+/);
  });

  it('says so when a metric is unavailable instead of rendering a blank', () => {
    // Every consumer of BI has a null branch; an empty card reads as "zero".
    const consumers = ['renderKpis', 'renderRetention', 'renderEngagement', 'drawBiTrend'];
    for (const fn of consumers) {
      const start = html.indexOf(`function ${fn}`);
      expect(start, `${fn} should exist`).toBeGreaterThan(-1);
      const body = html.slice(start, start + 2500);
      expect(body, `${fn} should handle BI being null`).toMatch(/if\s*\(\s*!BI/);
    }
  });
});
