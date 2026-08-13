/**
 * Frame 19 «Экстренные», executed in jsdom — the metric row, the SOS card and
 * the feed rows as a browser draws them.
 *
 * What it holds down:
 *  · the feed names the finding in Russian and prints the reading it fired on,
 *    instead of the literal «EMERGENCY» both repositories used to return;
 *  · every metric tile carries its explanation, and a tile whose input is
 *    missing prints «—» and says WHY, rather than a zero that reads as calm;
 *  · «ложных 61 %» / «реакция 1:40» from the design mock-up are computed from
 *    loaded rows or not shown at all;
 *  · an SOS gets its own card and does not render like a zone crossing;
 *  · the «Мы не служба спасения» plate is on the screen, and sentence 10 of
 *    docs/CLINICAL-REVIEW-WATCH.md («Мы вызвали скорую») is nowhere on it.
 */
import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const MIN = 60_000;
const iso = (msAgo: number) => new Date(Date.now() - msAgo).toISOString();

const STATS = { activeUsers: 3, devicesOnline: 2, alertsToday: 2, ingestLastHour: 9 };

/** The shape /admin/emergencies really answers with (see AdminEmergency). */
const EMERGENCIES = {
  emergencies: [
    {
      id: 'u1|a', userId: 'u1', displayName: 'Айгерім С.',
      code: 'PREECLAMPSIA_BP_SEVERE', severity: 'emergency', at: iso(10 * MIN),
      metric: 'systolicMmHg', value: 162, threshold: 160, systolic: 162, diastolic: 108,
      duringSleep: false, acknowledgedAt: null, acknowledgedBy: null,
    },
    {
      id: 'u2|b', userId: 'u2', displayName: 'Мадина К.',
      code: 'HYPOXIA_SEVERE', severity: 'emergency', at: iso(20 * MIN),
      metric: 'spo2Pct', value: 88, threshold: 90, systolic: null, diastolic: null,
      duringSleep: true, acknowledgedAt: iso(16 * MIN), acknowledgedBy: 's1',
    },
  ],
};

/** /admin/safety: newest first, two closed SOS and one crossing. */
const SAFETY = {
  events: [
    {
      userId: 'u1', displayName: 'Айгерім С.', childName: 'Сұлтан', kind: 'sos',
      zoneName: '', at: iso(30 * MIN), outcome: 'needed_help', phone: '+77073452244',
    },
    {
      userId: 'u2', displayName: 'Мадина К.', childName: 'Алия', kind: 'sos',
      zoneName: 'Двор', at: iso(200 * MIN), outcome: 'false_press', phone: '+77011189012',
    },
    {
      userId: 'u2', displayName: 'Мадина К.', childName: 'Алия', kind: 'entered',
      zoneName: 'Школа', at: iso(300 * MIN), outcome: null, phone: '+77011189012',
    },
  ],
};

interface BootOpts {
  emergencies?: unknown;
  emergenciesStatus?: number;
  safety?: unknown;
  safetyStatus?: number;
}

async function boot(opts: BootOpts = {}) {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const rejections: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const onRejection = (r: unknown) => rejections.push(String(r));
  process.on('unhandledRejection', onRejection);

  const dom = new JSDOM(html, {
    runScripts: 'dangerously', pretendToBeVisual: true, url: 'http://localhost/admin/ui',
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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.includes('/admin/stats')) return { ok: true, status: 200, json: async () => STATS };
        if (p.includes('/admin/emergencies')) {
          const st = opts.emergenciesStatus ?? 200;
          return { ok: st < 400, status: st, text: async () => '', json: async () => opts.emergencies ?? EMERGENCIES };
        }
        if (p.includes('/admin/safety')) {
          const st = opts.safetyStatus ?? 200;
          return { ok: st < 400, status: st, text: async () => '', json: async () => opts.safety ?? SAFETY };
        }
        return { ok: false, status: 500, text: async () => '', json: async () => ({}) };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 150));
  window.document.querySelector('[data-view="emergencies"]')?.dispatchEvent(
    new window.MouseEvent('click', { bubbles: true }),
  );
  await new Promise((r) => setTimeout(r, 300));
  process.off('unhandledRejection', onRejection);
  const txt = (sel: string) =>
    (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim();
  return { window, errors, rejections, txt };
}

describe('frame 19 — the feed says WHY', () => {
  it('names the finding in Russian with the reading and the threshold', async () => {
    const b = await boot();
    expect(b.errors).toEqual([]);
    expect(b.rejections).toEqual([]);

    const feed = b.txt('#feedFull');
    expect(feed).toContain('Давление в тяжёлом диапазоне');
    expect(feed).toContain('162/108 мм рт. ст.');
    expect(feed).toContain('порог 160');
    expect(feed).toContain('Очень низкий кислород');
    expect(feed).toContain('88 %');
    // The sleep flag changes what a sub-95 reading means; triage uses it, so
    // the row shows it.
    expect(feed).toContain('во сне');
    // The defect this frame was filed for.
    expect(feed).not.toContain('EMERGENCY');
    expect(feed).not.toContain('HYPOXIA');
  }, 30_000);

  it('admits it when the stored reading explains nothing', async () => {
    const b = await boot({
      emergencies: {
        emergencies: [{
          id: 'u9|z', userId: 'u9', displayName: 'Дана Т.', code: '', severity: 'emergency',
          at: iso(5 * MIN), metric: null, value: null, threshold: null,
          systolic: null, diastolic: null, duringSleep: false,
          acknowledgedAt: null, acknowledgedBy: null,
        }],
      },
    });
    expect(b.errors).toEqual([]);
    expect(b.txt('#feedFull')).toContain('Причина не сохранена');
  }, 30_000);
});

describe('frame 19 — the metric row', () => {
  it('counts from loaded rows and explains every tile', async () => {
    const b = await boot();
    const tiles = b.window.document.querySelectorAll('#emgMetrics .kpi');
    expect(tiles.length).toBe(4);
    // §3.6 / чек-лист: у каждой метрики есть поясняющая строка.
    tiles.forEach((t) => {
      expect((t.querySelector('.delta')?.textContent ?? '').trim().length).toBeGreaterThan(10);
    });

    const m = b.txt('#emgMetrics');
    // One of the two emergencies is unacknowledged. (textContent runs the tile's
    // label, value and note together, hence the tolerant separators.)
    expect(m).toMatch(/Неподтверждённые сигналы\s*1\s*из 2 загруженных/);
    // Median time to acknowledge: the acked one was cleared four minutes later.
    expect(m).toMatch(/Время до подтверждения\s*4 мин/);
    expect(m).toContain('медиана по подтверждённым: 1 из 2 загруженных');
    // Share of false presses, over CLOSED SOS only — one of two — with the
    // denominator on screen. The design's «61 %» is a mock-up's number and is
    // never printed.
    expect(m).toMatch(/Ложные нажатия SOS\s*50 %/);
    expect(m).toContain('1 из 2 закрытых SOS');
    expect(m).not.toContain('61 %');
  }, 30_000);

  it('refuses to compute a share when nothing has been closed', async () => {
    const b = await boot({
      safety: {
        events: [{
          userId: 'u1', displayName: 'Айгерім С.', childName: 'Сұлтан', kind: 'sos',
          zoneName: '', at: iso(15 * MIN), outcome: null, phone: '+77073452244',
        }],
      },
    });
    const m = b.txt('#emgMetrics');
    expect(m).toContain('ни один из загруженных SOS ещё не закрыт');
    expect(m).not.toContain('0 %');
  }, 30_000);

  it('counts nothing when the feed did not load, and does not call it quiet', async () => {
    const b = await boot({ emergenciesStatus: 500 });
    expect(b.errors).toEqual([]);
    const m = b.txt('#emgMetrics');
    expect(m).toContain('лента сигналов не загрузилась');
    const feed = b.txt('#feedFull');
    expect(feed).toContain('Ленту сигналов не удалось загрузить');
    expect(feed).not.toContain('Экстренных событий нет');
  }, 30_000);

  it('says «нет доступа» rather than «0» when the SOS table is refused', async () => {
    const b = await boot({ safetyStatus: 403 });
    expect(b.txt('#emgMetrics')).toContain('нет доступа к таблице SOS');
    expect(b.txt('#sosCard')).toContain('Нет доступа');
  }, 30_000);
});

describe('frame 19 — an SOS is not a zone crossing', () => {
  it('gives the newest SOS its own card with a number to call', async () => {
    const b = await boot();
    const card = b.window.document.querySelector('#sosCard');
    expect(card, 'no SOS card on the frame').not.toBeNull();
    const text = (card!.textContent ?? '').replace(/\s+/g, ' ').trim();

    expect(text).toContain('Последний SOS');
    expect(text).toContain('Сұлтан');           // the newest SOS, not the older one
    expect(text).not.toContain('Алия');
    // A crossing must not reach this card at all.
    expect(text).not.toContain('Школа');
    expect(b.txt('#safetyBody')).toContain('Школа');

    // Step 1 of the operator instruction is «Позвонить маме» — now possible.
    const tel = card!.querySelector('a[href^="tel:"]');
    expect(tel, 'no callable number on the SOS card').not.toBeNull();
    expect(tel!.getAttribute('href')).toBe('tel:+77073452244');
    expect(card!.querySelector('[data-user]')?.getAttribute('data-user')).toBe('u1');

    // How it ended, in Russian, from the column that was never selected.
    expect(text).toContain('Нужна была помощь');
    // And the map that is NOT drawn says so instead of being absent.
    expect(text).toContain('координаты вместе с сигналом не сохраняются');
  }, 30_000);

  it('separates «нет SOS» from «не смогли загрузить»', async () => {
    const b = await boot({
      safety: {
        events: [{
          userId: 'u2', displayName: 'Мадина К.', childName: 'Алия', kind: 'entered',
          zoneName: 'Школа', at: iso(30 * MIN), outcome: null, phone: '+77011189012',
        }],
      },
    });
    expect(b.txt('#sosCard')).toContain('нажатий SOS нет');
    const b2 = await boot({ safetyStatus: 500 });
    expect(b2.txt('#sosCard')).toContain('Не удалось загрузить');
  }, 30_000);
});

describe('frame 19 — the sentences it must and must not carry', () => {
  it('keeps the «Мы не служба спасения» plate and never claims an ambulance was called', async () => {
    const b = await boot();
    const view = b.txt('#emergencies');
    expect(view).toContain('Мы не служба спасения');
    expect(view).toContain('103');
    // docs/CLINICAL-REVIEW-WATCH.md, refused sentence 10. The reviewed pattern
    // is «Звоните 103», imperative — never a claim that WE called anyone.
    expect(view).not.toMatch(/вызвали скорую/i);
    expect(view).not.toMatch(/мы вызываем скорую/i);
    // …and sentence 9: no such channel exists.
    expect(view).not.toMatch(/сообщили вашему врачу/i);
  }, 30_000);
});
