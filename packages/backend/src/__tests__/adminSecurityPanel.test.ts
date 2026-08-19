/**
 * Render frames 22 «Безопасность» and 23a «Роли и права» and read what they
 * show.
 *
 * The payloads here are not hand-written JSON. The security summary comes from
 * the real `summarizeSecurity`, and the permission matrix from the real
 * `ROLE_CAPS` — the same values the routes serve. A fake that agreed with the
 * panel but not with the guards is exactly the failure these two screens exist
 * to prevent: a matrix that tells a manager one thing while the server enforces
 * another.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { summarizeSecurity, type AuditRow } from '../admin/security.js';
import { ALL_CAPABILITIES, ROLE_CAPS, STAFF_ROLES } from '../auth/capabilities.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const NOW = new Date('2026-08-08T12:00:00.000Z');
const at = (h: number) => new Date(NOW.getTime() - h * 3_600_000).toISOString();

const ROWS: AuditRow[] = [
  {
    staffId: 's1', staffName: 'Ерен', action: 'view_health',
    target: 'u1', targetName: 'Айгерім', reason: 'Разбор жалобы', at: at(2),
  },
  {
    staffId: 's1', staffName: 'Ерен', action: 'view_user_detail',
    target: 'u2', targetName: 'Мадина', reason: 'Звонок в поддержку', at: at(5),
  },
  // The one with no reason — the number the screen exists to make visible.
  {
    staffId: 's2', staffName: 'Асем', action: 'view_devices',
    target: 'u3', targetName: 'Айнур', reason: null, at: at(9),
  },
  // Not special-category, so it must not be counted or listed here.
  {
    staffId: 's2', staffName: 'Асем', action: 'stock_move',
    target: null, targetName: null, reason: null, at: at(1),
  },
];

const SECURITY = {
  ...summarizeSecurity(ROWS, NOW, 30),
  retention: { routeDays: 90, auditSweep: null },
};

const ROLES = {
  roles: STAFF_ROLES.map((role) => ({ role, caps: ROLE_CAPS[role] })),
  caps: ALL_CAPABILITIES.map((cap) => ({
    cap,
    special: cap === 'health' || cap === 'emergencies',
  })),
  you: 'owner',
};

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  html(sel: string): string;
  errors: string[];
  window: JSDOM['window'];
}

async function render(
  view: string,
  down: string[] = [],
  security: Record<string, unknown> = SECURITY,
): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin/ui',
    virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          {
            canvas: { width: 600, height: 170 },
            createLinearGradient: () => ({ addColorStop: noop }),
            measureText: () => ({ width: 10 }),
          },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
        );
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'owner' }) };
        }
        if (down.some((d) => p.includes(d))) {
          return { ok: false, status: 500, json: async () => ({}) };
        }
        const body = p.includes('/admin/security') ? security
          : p.includes('/admin/roles') ? ROLES
            : {};
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(120);
  window.document
    .querySelector(`[data-view="${view}"]`)!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(120);

  const norm = (s: string) => s.replace(/\s+/g, ' ').trim();
  return {
    text: (sel) => norm(window.document.querySelector(sel)?.textContent ?? ''),
    count: (sel) => window.document.querySelectorAll(sel).length,
    html: (sel) => window.document.querySelector(sel)?.innerHTML ?? '',
    errors,
    window,
  };
}

// ---------------------------------------------------------------------------

describe('frame 22 · Безопасность', () => {
  let page: Rendered;
  beforeAll(async () => { page = await render('security'); });

  it('runs without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('leads with the count of protected reads, split by kind', () => {
    const t = page.text('#secKpis');
    expect(t).toContain('Просмотров защищённых данных');
    expect(t).toContain('Здоровье');
    expect(t).toContain('Геолокация');
    // Two health reads, one location — and the stock move excluded.
    expect(page.count('#secKpis .kpi')).toBe(4);
    expect(t).toContain('за 30 дн.');
  });

  it('shows the unexplained read as a problem, not as a number', () => {
    // The tile is coloured only when it is non-zero: a permanently red tile
    // stops being read, which is how the one that matters gets missed.
    const html = page.html('#secKpis');
    expect(html).toContain('--crit-text');
    expect(page.text('#secKpis')).toContain('нужно разобраться');
  });

  it('lists the reads with who, whose and why — in Russian, not action keys', () => {
    const t = page.text('#secBody');
    expect(t).toContain('Ерен');
    expect(t).toContain('Айгерім');
    expect(t).toContain('Разбор жалобы');
    // The label map used to miss this key entirely and print it raw.
    expect(t).toContain('Открыл(а) карточку пациентки');
    expect(t).not.toContain('view_user_detail');
  });

  it('says «не указано» where a reason is missing, rather than a dash', () => {
    // A dash reads as "nothing to see". This row is the whole point of the page.
    expect(page.text('#secBody')).toContain('не указано');
  });

  it('leaves ordinary back-office work out of it', () => {
    // Counting stock moves as privacy events buries the reads that are.
    expect(page.text('#secBody')).not.toContain('Движение по складу');
    expect(page.count('#secBody tr')).toBe(3);
  });

  it('names who has been looking, most active first', () => {
    const t = page.text('#secStaffBody');
    expect(t).toContain('Ерен');
    expect(t).toContain('Асем');
    expect(t.indexOf('Ерен')).toBeLessThan(t.indexOf('Асем'));
  });

  it('quotes the retention periods it was given', () => {
    const t = page.text('#secRetention');
    expect(t).toContain('Маршруты детей');
    expect(t).toContain('90');
    expect(t).toContain('Журнал доступа');
    // It must NOT quote a period for the audit log. This assertion used to be
    // toContain('3'), which pinned the false claim: the panel printed «3 года»
    // beside the real, scheduled 90-day route sweep, while nothing has ever
    // deleted an audit_log row. A reviewer read two enforced periods where
    // only one exists.
    expect(t).toContain('срок не задан');
    expect(t).not.toContain('года');
  });

  it('ends on the open question rather than settling it quietly', () => {
    expect(page.text('#security')).toContain('Открытый вопрос');
  });

  it('re-asks the server when the period changes', async () => {
    // Filtering what is already drawn would leave the tiles stating a total for
    // one window above a table showing another.
    const p = await render('security');
    const sel = p.window.document.querySelector('#secDays') as HTMLSelectElement;
    sel.value = '7';
    sel.dispatchEvent(new p.window.Event('change', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 80));
    expect(p.errors).toEqual([]);
    expect(p.text('#secKpis').length).toBeGreaterThan(10);
  });
});

describe('frame 22 · when the journal cannot be loaded', () => {
  let page: Rendered;
  beforeAll(async () => { page = await render('security', ['/admin/security']); });

  it('says so instead of reporting zero', () => {
    // "0 просмотров" on a screen that failed to load is worse than silence —
    // this is the page somebody opens to be sure nothing is wrong.
    expect(page.text('#secBody')).toContain('Не удалось загрузить');
    expect(page.text('#secKpis')).toBe('');
  });
});

// ---------------------------------------------------------------------------

describe('frame 23a · Роли и права', () => {
  let page: Rendered;
  beforeAll(async () => { page = await render('roles'); });

  it('runs without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('draws every capability against every role', () => {
    expect(page.count('#rolesBody tr')).toBe(ALL_CAPABILITIES.length);
    // One header cell per role, plus the leading «Право» column.
    expect(page.count('#rolesHead th')).toBe(STAFF_ROLES.length + 1);
  });

  it('names the roles and the rights in Russian', () => {
    const head = page.text('#rolesHead');
    for (const label of ['Владелец', 'Оператор', 'Продавец', 'Склад', 'Контент-редактор']) {
      expect(head).toContain(label);
    }
    expect(page.text('#rolesBody')).toContain('Здоровье, дети и геолокация');
  });

  it('highlights the special-category rows', () => {
    // «строки здоровья и геолокации подсвечены #FBF0F3»
    expect(page.count('#rolesBody tr[style*="FBF0F3"]')).toBe(2);
  });

  it('agrees with the guards, cell by cell', () => {
    // The assertion that makes this screen worth trusting: what is drawn is
    // read back and compared against ROLE_CAPS itself. A matrix that drifts
    // from the guards is the one failure this frame cannot be allowed.
    const rows = [...page.window.document.querySelectorAll('#rolesBody tr')];
    expect(rows).toHaveLength(ALL_CAPABILITIES.length);
    rows.forEach((tr, i) => {
      const cap = ALL_CAPABILITIES[i];
      const cells = [...tr.querySelectorAll('td')].slice(1);
      expect(cells).toHaveLength(STAFF_ROLES.length);
      cells.forEach((td, j) => {
        const role = STAFF_ROLES[j];
        const drawn = (td.textContent ?? '').includes('✓');
        expect(drawn, `${role} × ${cap} drawn as ${drawn}`)
          .toBe(ROLE_CAPS[role].includes(cap));
      });
    });
  });

  it('says a tick in words too, not in colour alone', () => {
    // Colour says nothing to a screen reader or to a printed copy, and this
    // table gets printed.
    const first = page.window.document.querySelector('#rolesBody td + td');
    expect(first?.getAttribute('title')).toMatch(/(да|нет)$/);
  });

  it('marks the row of the person reading it', () => {
    expect(page.text('#rolesHead')).toContain('вы');
  });
});

// ---------------------------------------------------------------------------

describe('the two security tabs do not collide with the SOS feed', () => {
  it('no two navigation items share a label', async () => {
    // «Безопасность» named both the SOS feed and this new screen. Two tabs with
    // one name is how somebody looking for the access log lands on a map of
    // children.
    const page = await render('security');
    const labels = [...page.window.document.querySelectorAll('.nav')]
      .filter((n) => !(n as HTMLElement).hidden)
      .map((n) => (n.textContent ?? '').replace(/\s+/g, ' ').trim())
      .filter(Boolean);
    expect(new Set(labels).size).toBe(labels.length);
  });
});

/** «Hidden vs painted»: a display rule beats the hidden attribute. */
function painted(p: Rendered, sel: string): boolean {
  const el = p.window.document.querySelector(sel) as HTMLElement | null;
  if (!el) return false;
  for (let n: HTMLElement | null = el; n; n = n.parentElement) {
    if (n.hasAttribute('hidden')) return false;
    if (n.classList.contains('view') && !n.classList.contains('active')) return false;
  }
  return true;
}

describe('a count that stopped at the row cap says so', () => {
  /**
   * The figure a regulator is shown must never be a floor presented as a total.
   *
   * The server now filters the window in SQL, but any query has a ceiling; when
   * it is reached the answer carries `truncated`, and this screen is where that
   * has to become a sentence. «Защищённых просмотров: 12» over an unknown slice
   * of twelve months is the original defect with a different number in it.
   */
  it('shows the warning and prints the tiles as floors', async () => {
    // withoutReason: 0 deliberately — the reassuring zero, counted over a slice
    // of unknown size. That pair is the whole reason this warning exists.
    const page = await render('security', [], {
      ...SECURITY, withoutReason: 0, truncated: true, rowCap: 20000,
    });
    expect(page.errors, page.errors.join('\n')).toEqual([]);
    expect(painted(page, '#secTruncated'), 'a truncated count was drawn as a total').toBe(true);
    expect(page.text('#secTruncated')).toContain('Показан не весь период');
    // The cap is named, because «слишком много» without a number is not
    // something anybody can act on.
    expect(page.text('#secTruncated')).toContain('20000');
    // ≥, not a bare integer.
    expect(page.text('#secKpis')).toContain('≥');
    // And «без основания: 0» must stop reading as «как и должно быть».
    expect(page.text('#secKpis')).toContain('по неполному срезу');
  });

  it('and stays out of the way when the slice was whole', async () => {
    // A warning shown always is a warning read never.
    const page = await render('security', [], { ...SECURITY, withoutReason: 0 });
    expect(painted(page, '#secTruncated')).toBe(false);
    expect(page.text('#secKpis')).not.toContain('≥');
    expect(page.text('#secKpis')).toContain('как и должно быть');
  });
});
