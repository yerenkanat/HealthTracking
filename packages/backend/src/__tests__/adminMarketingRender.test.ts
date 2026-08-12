/**
 * Render кадр 06 «Маркетинг» for real (jsdom), and press its buttons.
 *
 * The routes are proved end to end in broadcasts.test.ts. This is the other
 * half of the same defect: a panel that renders a table and a form which are
 * wired to nothing looks identical to a working one until a marketer reports
 * that «Отправить» did nothing — and this is the screen where being wrong is
 * delivered to strangers' phones rather than displayed to a colleague.
 *
 * So nothing below is asserted structurally. Every expectation is on text a
 * browser painted, on the `disabled` property of a real button, or on the
 * request the panel actually sent.
 */
import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const PUBLISHED = {
  id: 'bc-1', titleRu: 'Второй скрининг', bodyRu: 'Окно 18–21 неделя.',
  titleKk: 'Екінші скрининг', bodyKk: '18–21 апта.',
  segment: { audience: 'pregnant' }, status: 'published', createdBy: 's1',
  createdAt: '2026-08-01T09:00:00Z', updatedAt: '2026-08-02T09:00:00Z',
  publishedAt: '2026-08-02T09:00:00Z', delivered: 12,
};

/** A draft with no Kazakh half — the row the table must mark as unsendable. */
const HALF_TRANSLATED = {
  id: 'bc-2', titleRu: 'Витамин D', bodyRu: 'Зимой стоит обсудить с врачом.',
  titleKk: null, bodyKk: null,
  segment: { audience: 'mothers', locale: 'ru' }, status: 'draft', createdBy: 's1',
  createdAt: '2026-08-05T09:00:00Z', updatedAt: '2026-08-05T09:00:00Z',
  publishedAt: null, delivered: 0,
};

function listBody(broadcasts: unknown[]) {
  return {
    broadcasts,
    minGapDays: 7,
    audiences: ['all', 'pregnant', 'mothers', 'infants'],
    locales: ['ru', 'kk'],
    segmentFields: ['audience', 'locale'],
    infantMaxMonths: 12,
  };
}

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  errors: string[];
  sent: Array<{ method: string; path: string; body: unknown }>;
  window: import('jsdom').DOMWindow;
}

interface BootOpts {
  role?: string;
  broadcasts?: unknown[];
  /** Make GET /admin/broadcasts fail, to see what the tab then says. */
  listStatus?: number;
  listMessage?: string;
  /** What GET /admin/broadcasts/:id/preview answers. */
  preview?: { status?: number; body: unknown };
  /** What POST …/publish answers. */
  publishReply?: { status: number; body: unknown };
  confirm?: boolean;
}

async function boot(opts: BootOpts = {}): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const sent: Rendered['sent'] = [];
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
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
        );
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      window.confirm = () => opts.confirm !== false;
      (window as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s) => s };
      window.fetch = (async (path: string, init?: { method?: string; body?: string }) => {
        const p = String(path);
        const method = init?.method ?? 'GET';
        if (method !== 'GET') {
          sent.push({ method, path: p, body: init?.body ? JSON.parse(init.body) : null });
        }
        const ok = (body: unknown, status = 200) => ({
          ok: status >= 200 && status < 300, status,
          text: async () => JSON.stringify(body),
          json: async () => body,
        });
        if (p.includes('/admin/me')) return ok({ staffId: 's1', role: opts.role ?? 'admin' });
        // Longest match first: /preview lives under /admin/broadcasts.
        if (p.includes('/preview')) {
          const r = opts.preview ?? {
            body: { segment: { audience: 'all' }, matched: 40, excluded: 0, deliverable: 40, minGapDays: 7, describe: 'Все' },
          };
          return ok(r.body, r.status ?? 200);
        }
        if (p.includes('/admin/broadcasts') && method === 'POST' && p.endsWith('/publish')) {
          const r = opts.publishReply ?? {
            status: 200,
            body: { ok: true, id: 'bc-x', matched: 40, excluded: 3, delivered: 37, pushed: true, minGapDays: 7 },
          };
          return ok(r.body, r.status);
        }
        if (p.includes('/admin/broadcasts') && method !== 'GET') return ok({ ok: true });
        if (p.includes('/admin/broadcasts')) {
          if (opts.listStatus && opts.listStatus >= 400) {
            return ok({ error: 'broadcasts_unavailable', message: opts.listMessage ?? 'Таблица рассылок недоступна.' }, opts.listStatus);
          }
          return ok(listBody(opts.broadcasts ?? [PUBLISHED, HALF_TRANSLATED]));
        }
        return { ok: false, status: 500, text: async () => '{}', json: async () => ({}) };
      }) as never;
    },
  });
  const { window } = dom;
  await new Promise((r) => setTimeout(r, 120));
  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => window.document.querySelectorAll(sel).length,
    errors,
    sent,
    window,
  };
}

async function click(page: Rendered, sel: string) {
  page.window.document.querySelector(sel)!.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 120));
}

/** Type, and fire the event the panel actually listens for. */
async function type(page: Rendered, sel: string, value: string) {
  const el = page.window.document.querySelector(sel) as HTMLInputElement;
  el.value = value;
  el.dispatchEvent(new page.window.Event('input', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 20));
}

/** See adminPregWeeksRender: `hidden` plus "is this the open tab". */
function painted(page: Rendered, sel: string): boolean {
  const el = page.window.document.querySelector(sel) as HTMLElement | null;
  if (!el) return false;
  for (let n: HTMLElement | null = el; n; n = n.parentElement) {
    if (n.hasAttribute('hidden')) return false;
    if (n.classList.contains('view') && !n.classList.contains('active')) return false;
  }
  return true;
}

async function open(opts: BootOpts = {}): Promise<Rendered> {
  const page = await boot(opts);
  await click(page, '[data-view="marketing"]');
  return page;
}

describe('the marketing tab draws', () => {
  it('boots, opens, and is the tab a browser would be showing', async () => {
    const page = await open();
    expect(page.errors).toEqual([]);
    // Not vacuous: nothing in this section is "painted" from another tab.
    const other = await boot();
    expect(painted(other, '#bcFormCard')).toBe(false);
    expect(painted(page, '#bcFormCard')).toBe(true);
  });

  it('lists what was sent, to whom, and how many got it', async () => {
    const page = await open();
    expect(page.count('#bcBody tr')).toBe(2);
    const first = page.text('#bcBody tr[data-bc="bc-1"]');
    expect(first).toContain('Второй скрининг');
    expect(first).toContain('Беременные');
    expect(first).toContain('Отправлена');
    expect(first).toContain('12');
    expect(page.text('#bcSummary')).toBe('2 всего · 1 отправлено · 1 в черновиках');
  });

  it('marks a draft that cannot be sent, rather than leaving it to be discovered', async () => {
    const page = await open();
    const row = page.text('#bcBody tr[data-bc="bc-2"]');
    expect(row).toContain('Черновик');
    expect(row).toContain('нет қаз');
    // A draft has no delivered count to print, and prints no zero either — a
    // zero would read as «ушло никому».
    expect(row).toContain('—');
  });

  it('says there has never been one, instead of an empty table', async () => {
    const page = await open({ broadcasts: [] });
    expect(page.text('#bcBody')).toContain('Рассылок ещё не было');
  });

  it('a table it could not read says so, and does not offer to send over it', async () => {
    const page = await open({ listStatus: 503, listMessage: 'Не удалось прочитать таблицу рассылок (broadcasts).' });
    expect(page.text('#bcBody')).toContain('Не удалось загрузить рассылки');
    expect(page.text('#bcBody')).toContain('broadcasts');
    // An empty table and an unreadable one are opposite claims.
    expect(page.text('#bcBody')).not.toContain('Рассылок ещё не было');
  });
});

describe('the footer states the rule the database enforces', () => {
  it('names the seven days, and refuses to imply a read rate', async () => {
    const page = await open();
    const rule = page.text('#bcRule');
    expect(rule).toContain('раз в 7 дн.');
    expect(rule).toContain('по всем рассылкам сразу');
    // «Доставлено», never «прочитано»: nothing in this product records whether
    // a notification was opened, so there is no such number to print.
    expect(rule).toContain('Не «прочитано»');
    expect(rule).not.toMatch(/прочитали\s+\d/);
    // And where the audience comes from — the three honest columns.
    expect(rule).toContain('users.locale');
    expect(rule).toContain('users.due_date');
    expect(rule).toContain('children.date_of_birth');
    expect(rule).toContain('по показателям здоровья выбирать получателей нельзя');
  });
});

describe('«Отправить» is dead without the Kazakh half', () => {
  const publish = (page: Rendered) =>
    page.window.document.querySelector('#bcPublish') as HTMLButtonElement;

  it('starts disabled on an empty form and says why', async () => {
    const page = await open();
    expect(publish(page).disabled).toBe(true);
    expect(publish(page).title).toContain('казахской версии');
  });

  it('stays disabled with only the Russian half typed', async () => {
    const page = await open();
    await type(page, '#bcTitleRu', 'Второй скрининг');
    await type(page, '#bcBodyRu', 'Окно 18–21 неделя.');
    expect(publish(page).disabled).toBe(true);
  });

  it('comes alive the moment all four boxes have text, and dies again when one is cleared', async () => {
    const page = await open();
    await type(page, '#bcTitleRu', 'Второй скрининг');
    await type(page, '#bcBodyRu', 'Окно 18–21 неделя.');
    await type(page, '#bcTitleKk', 'Екінші скрининг');
    await type(page, '#bcBodyKk', '18–21 апта.');
    expect(publish(page).disabled).toBe(false);
    expect(publish(page).title).toBe('');

    await type(page, '#bcBodyKk', '');
    expect(publish(page).disabled).toBe(true);
  });

  it('opening a half-translated draft leaves the button dead', async () => {
    const page = await open();
    await click(page, '[data-bcedit="bc-2"]');
    expect(page.text('#bcFormH')).toContain('Витамин D');
    expect(publish(page).disabled).toBe(true);
  });

  it('«Сохранить черновик» still works on it — a draft may be half-written', async () => {
    const page = await open();
    await click(page, '[data-bcedit="bc-2"]');
    await click(page, '#bcSave');
    const put = page.sent.find((r) => r.method === 'PUT');
    expect(put, 'the draft was never saved').toBeTruthy();
    expect(put!.path).toContain('/admin/broadcasts/bc-2');
    expect(page.text('#bcMsg')).toContain('ещё никому не ушёл');
  });
});

describe('the recipient count comes from the server', () => {
  it('prints both numbers when some of the audience is inside the gap', async () => {
    const page = await open({
      preview: { body: { segment: {}, matched: 40, excluded: 28, deliverable: 12, minGapDays: 7, describe: 'Все' } },
    });
    const count = page.text('#bcCount');
    expect(count).toContain('Получат сейчас: 12 из 40');
    expect(count).toContain('28 пропустим');
    expect(count).toContain('7 дн.');
  });

  it('asks the server again when the audience changes — it never computes one here', async () => {
    const page = await open();
    const seen: string[] = [];
    const original = page.window.fetch;
    (page.window as unknown as { fetch: unknown }).fetch = ((p: string, init?: unknown) => {
      if (String(p).includes('/preview')) seen.push(String(p));
      return (original as (a: string, b?: unknown) => unknown)(p, init);
    }) as never;

    const sel = page.window.document.querySelector('#bcAudience') as HTMLSelectElement;
    sel.value = 'infants';
    sel.dispatchEvent(new page.window.Event('change', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 250));

    expect(seen.length, 'the browser answered the head-count itself').toBeGreaterThan(0);
    expect(decodeURIComponent(seen[0])).toContain('"audience":"infants"');
  });

  it('says the counter is unavailable rather than printing a zero it did not get', async () => {
    const page = await open({
      preview: { status: 400, body: { error: 'segment_health_forbidden', message: 'Нельзя выбирать получателей по полю «systolic».' } },
    });
    expect(page.text('#bcCount')).toContain('Счётчик недоступен');
    expect(page.text('#bcCount')).toContain('systolic');
    expect(page.text('#bcCount')).not.toContain('Получат сейчас: 0');
  });
});

describe('sending', () => {
  async function fill(page: Rendered) {
    await type(page, '#bcTitleRu', 'Второй скрининг');
    await type(page, '#bcBodyRu', 'Окно 18–21 неделя.');
    await type(page, '#bcTitleKk', 'Екінші скрининг');
    await type(page, '#bcBodyKk', '18–21 апта.');
  }

  it('confirms first — it is irreversible and it reaches strangers', async () => {
    const page = await open({ confirm: false });
    await fill(page);
    await click(page, '#bcPublish');
    expect(page.sent.filter((r) => r.path.endsWith('/publish'))).toHaveLength(0);
  });

  it('saves what is on screen and then publishes that, in that order', async () => {
    const page = await open();
    await fill(page);
    await click(page, '#bcPublish');
    const writes = page.sent.filter((r) => r.path.includes('/admin/broadcasts'));
    expect(writes[0].method).toBe('POST');
    expect(writes[0].path).toBe('/admin/broadcasts');
    expect(writes[0].body).toMatchObject({
      titleRu: 'Второй скрининг', titleKk: 'Екінші скрининг', bodyKk: '18–21 апта.',
      segment: { audience: 'all' },
    });
    expect(writes[1].path).toContain('/publish');
  });

  it('reports delivered AND skipped, not a bare «отправлено»', async () => {
    const page = await open();
    await fill(page);
    await click(page, '#bcPublish');
    const msg = page.text('#bcMsg');
    expect(msg).toContain('Отправлено 37 из 40');
    expect(msg).toContain('3 пропущено');
    expect(msg).toContain('7 дн.');
  });

  it('says the push failed while still saying the message was delivered', async () => {
    const page = await open({
      publishReply: { status: 200, body: { ok: true, matched: 5, excluded: 0, delivered: 5, pushed: false, minGapDays: 7 } },
    });
    await fill(page);
    await click(page, '#bcPublish');
    expect(page.text('#bcMsg')).toContain('Отправлено 5 из 5');
    expect(page.text('#bcMsg')).toContain('Уведомления на телефоны не ушли');
    expect(page.text('#bcMsg')).toContain('всё равно лежит в приложении');
  });

  it('paints the server\'s own sentence when the send is refused', async () => {
    const page = await open({
      publishReply: {
        status: 400,
        body: { error: 'translation_required', message: '«Второй скрининг»: нет казахской версии. Без казахской версии рассылку отправить нельзя.' },
      },
    });
    await fill(page);
    await click(page, '#bcPublish');
    expect(page.text('#bcMsg')).toContain('Без казахской версии рассылку отправить нельзя');
  });
});

describe('who may open it', () => {
  it('hides the constructor from a role without `content`', async () => {
    // A warehouse hand has no business writing to forty thousand people.
    const page = await open({ role: 'warehouse' });
    expect(painted(page, '#bcFormCard')).toBe(false);
    expect(painted(page, '#bcPublish')).toBe(false);
  });
});
