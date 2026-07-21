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

  it('the analytics tab renders the product metrics it fetches', () => {
    // The product metrics live on «Аналитика» now, and the overview keeps the
    // operational view. What each tab SHOWS is asserted by executing the page
    // in adminPanelRender.test.ts; this only pins that the elements exist.
    expect(html).toContain('/admin/bi');
    for (const id of ['anKpis', 'anTrend', 'anRetCurve', 'anGrowth', 'anFunnel', 'anAdoption', 'biRetention', 'biEngagement']) {
      expect(definedIds().has(id), `analytics should contain #${id}`).toBe(true);
    }
    for (const id of ['kpis', 'opsTrend', 'feedMini']) {
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

  it('has exactly one staff identity', () => {
    // There were two, in two script blocks: the dashboard half sent role
    // "clinician" and the CMS half sent "admin". The same person was two
    // different staff members depending on which button they pressed — reads
    // authorized as a clinician, content edits as an admin, both audited under
    // the same id. Whichever was intended, one of them was wrong.
    const declarations = [...html.matchAll(/const\s+STAFF\s*=/g)];
    expect(declarations).toHaveLength(1);
    const roles = [...html.matchAll(/role:\s*"(admin|clinician|support)"/g)].map((m) => m[1]);
    expect(new Set(roles).size, `panel claims several roles: ${roles.join(', ')}`).toBeLessThanOrEqual(1);
  });

  it('tells a staff member their access was refused', () => {
    // 401/403 and "the server did not answer" used to throw the same thing,
    // and the catch quietly showed demo numbers. Someone whose access had been
    // revoked got a complete, plausible dashboard of invented figures.
    expect(html).toMatch(/class AccessDenied/);
    expect(html).toMatch(/status\s*===\s*401\s*\|\|\s*r\.status\s*===\s*403/);
    expect(html).toContain('Нет доступа');
  });

  it('says so when a metric is unavailable instead of rendering a blank', () => {
    // Every consumer of BI has a null branch; an empty card reads as "zero".
    //
    // renderKpis is no longer on the list: the overview shows operational
    // counters that do not come from /admin/bi at all, so it renders fully
    // with BI null and has nothing to guard. Its one BI-derived tile falls
    // back inline. That it does so is checked by rendering the page.
    const consumers = ['renderRetention', 'renderEngagement', 'drawBiTrend', 'renderGrowth', 'renderFunnel', 'renderAdoption'];
    for (const fn of consumers) {
      const start = html.indexOf(`function ${fn}`);
      expect(start, `${fn} should exist`).toBeGreaterThan(-1);
      const body = html.slice(start, start + 2500);
      expect(body, `${fn} should handle BI being null`).toMatch(/if\s*\(\s*!BI/);
    }
  });
});
