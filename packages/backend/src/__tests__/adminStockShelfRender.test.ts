/**
 * Frame 07 · Остатки, drawn in a browser.
 *
 * The owner opened «Товары и остатки» and found a flat list of coloured dots:
 * no picture of anything, no «Хватит на» column to scan, and nothing at all
 * about what moved today — while the storefront beside it shows real photos of
 * the same colours and the ledger has been recording every movement with its
 * author and reason all along.
 *
 * Everything here is asserted against a rendered DOM rather than against the
 * source, because the failure being guarded against is precisely a screen that
 * "has the code for it" and paints something else.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const TODAY = new Date();
const at = (minutesAgo: number) => new Date(TODAY.getTime() - minutesAgo * 60_000).toISOString();

/// The one colour we hold a picture of, named once so the fixture and the
/// assertion cannot drift apart.
const PHOTOGRAPHED = {
  color: 'Розовое золото',
  url: '/shop/products/watch/photo?color=%D0%A0%D0%BE%D0%B7%D0%BE%D0%B2%D0%BE%D0%B5%20%D0%B7%D0%BE%D0%BB%D0%BE%D1%82%D0%BE',
};

/**
 * The owner's actual shelf: everything at zero. «Хватит на 0 дн.» is true and
 * useless, and the rate behind it does not exist — there is nothing to divide.
 */
const INVENTORY = {
  windowDays: 30,
  leadTimeDays: 14,
  reorder: ['strap'],
  lowStock: [],
  reorderCovered: [],
  products: [
    {
      id: 'watch', name: 'Часы Ana-Bala', sku: 'AB-WATCH-01',
      priceMinor: 2490000, costMinor: 1500000, kind: 'simple', active: true,
      stock: 0, lowStock: true, lowStockThreshold: 3, parts: [],
      soldInWindow: 0, perDay: 0, daysOfCover: null, noSales: true,
      reorder: false, reorderCovered: false, inTransit: 12,
      variants: [
        // Photographed for the storefront — the warehouse must show the same one.
        { id: 'v1', color: PHOTOGRAPHED.color, colorHex: '#E8B4A0', stock: 0, inTransit: 12,
          photoUrl: PHOTOGRAPHED.url, photoUpdatedAt: at(6000) },
        // Never photographed. The commonest state, and it must not read as a fault.
        { id: 'v2', color: 'Чёрный', colorHex: '#1C1E2A', stock: 0, inTransit: 0 },
      ],
    },
    {
      id: 'strap', name: 'Ремешок', sku: null,
      priceMinor: 350000, costMinor: null, kind: 'simple', active: true,
      stock: 24, lowStock: false, lowStockThreshold: 3, parts: [],
      soldInWindow: 180, perDay: 6, daysOfCover: 4, noSales: false,
      reorder: true, reorderCovered: false, inTransit: 0,
      variants: [{ id: 'v3', color: 'Синий', colorHex: '#48f', stock: 24, inTransit: 0 }],
    },
    {
      // Two left against a threshold of three, and nothing sold in the window.
      // The ONLY rule that can have put this on the amber plate is the number
      // somebody typed in by hand — the sales rate has nothing to say about it.
      id: 'mini', name: 'Ремешок мини', sku: null,
      priceMinor: 290000, costMinor: null, kind: 'simple', active: true,
      stock: 2, lowStock: true, lowStockThreshold: 3, parts: [],
      soldInWindow: 0, perDay: 0, daysOfCover: null, noSales: true,
      reorder: false, reorderCovered: false, inTransit: 0,
      variants: [{ id: 'v6', color: 'Серый', colorHex: '#888', stock: 2, inTransit: 0 }],
    },
    {
      // Sold out, and it WAS selling: the arithmetic here really does produce
      // zero days of cover. «Хватит на 0 дн.» is true and useless — the shelf
      // is empty, and the buyer's question is what is coming, not the forecast.
      id: 'holder', name: 'Держатель', sku: null,
      priceMinor: 190000, costMinor: null, kind: 'simple', active: true,
      stock: 0, lowStock: true, lowStockThreshold: 3, parts: [],
      soldInWindow: 90, perDay: 3, daysOfCover: 0, noSales: false,
      reorder: true, reorderCovered: false, inTransit: 0,
      variants: [{ id: 'v5', color: 'Белый', colorHex: '#fff', stock: 0, inTransit: 0 }],
    },
    {
      // Full shelf, nobody buying. The rate is UNKNOWN, not zero — «хватит
      // навсегда» would be the invented number.
      id: 'tag', name: 'Брелок', sku: null,
      priceMinor: 990000, costMinor: null, kind: 'simple', active: true,
      stock: 15, lowStock: false, lowStockThreshold: 3, parts: [],
      soldInWindow: 0, perDay: 0, daysOfCover: null, noSales: true,
      reorder: false, reorderCovered: false, inTransit: 0,
      variants: [{ id: 'v4', color: 'Бирюзовый', colorHex: '#12B3A6', stock: 15, inTransit: 0 }],
    },
  ],
};

const DAY_MOVES = [
  { id: 3, variantId: 'v3', productName: 'Ремешок', color: 'Синий', delta: -2,
    reason: 'sale', note: null, staffId: 'anna', orderId: 'o1', at: at(30) },
  { id: 2, variantId: 'v3', productName: 'Ремешок', color: 'Синий', delta: -1,
    reason: 'writeoff', note: 'порвался на витрине', staffId: 'anna', orderId: null, at: at(90) },
  { id: 1, variantId: 'v3', productName: 'Ремешок', color: 'Синий', delta: 27,
    reason: 'receipt', note: 'накладная 118', staffId: 'ерен', orderId: null, at: at(300) },
];

interface Opts {
  inventoryFails?: boolean;
  dayFails?: boolean;
  dayExact?: boolean;
  dayMoves?: typeof DAY_MOVES;
  /** What window.confirm answers when «Списать» asks. */
  confirmAnswer?: boolean;
}

interface Page {
  window: JSDOM['window'];
  errors: string[];
  /** Every path the panel asked for, in order. */
  asked: string[];
  /** Every write it attempted, so a refused confirmation can be proved. */
  posted: Array<{ path: string; body: unknown }>;
  text: (sel: string) => string;
  all: (sel: string) => Element[];
}

async function render(o: Opts = {}): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const asked: string[] = [];
  const posted: Array<{ path: string; body: unknown }> = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin',
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
      (window as unknown as { alert: (m: string) => void }).alert = () => {};
      (window as unknown as { confirm: () => boolean }).confirm = () => o.confirmAnswer ?? true;
      (window as unknown as { prompt: () => string }).prompt = () => 'брак';

      window.fetch = (async (path: string, init?: { method?: string; body?: string }) => {
        const p = String(path);
        asked.push(p);
        if (init?.method && init.method !== 'GET') {
          posted.push({ path: p, body: init.body ? JSON.parse(init.body) : null });
          return { ok: true, status: 200, text: async () => '', json: async () => ({ ok: true, stock: 0 }) };
        }
        // Order matters: '/admin/inventory' is a prefix of the moves path, and
        // «за день» is the moves path WITH a since.
        if (p.includes('/admin/inventory/moves')) {
          if (p.includes('since=')) {
            if (o.dayFails) return { ok: false, status: 500, text: async () => '', json: async () => ({}) };
            const moves = o.dayMoves ?? DAY_MOVES;
            return { ok: true, status: 200, text: async () => '',
              json: async () => ({ moves, limit: 500, since: null, exact: o.dayExact ?? true }) };
          }
          return { ok: true, status: 200, text: async () => '', json: async () => ({ moves: [] }) };
        }
        if (p.includes('/admin/inventory')) {
          if (o.inventoryFails) return { ok: false, status: 500, text: async () => '', json: async () => ({}) };
          return { ok: true, status: 200, text: async () => '', json: async () => INVENTORY };
        }
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
          : p.includes('/admin/device-registry') ? { devices: [] }
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 200));
  window.document.querySelector('[data-view="stock"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 320));

  return {
    window, errors, asked, posted,
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    all: (sel) => [...window.document.querySelectorAll(sel)],
  };
}

describe('the shelf shows the photo the customer sees', () => {
  it('renders without throwing', async () => {
    const page = await render();
    expect(page.errors, page.errors.join('\n')).toEqual([]);
  });

  it('draws the colour photo where there is one', async () => {
    const page = await render();
    const imgs = page.all('#stockBody img.thumb') as HTMLImageElement[];
    expect(imgs.length, 'the photographed colour is still a coloured dot').toBe(1);
    expect(imgs[0].getAttribute('src')).toBe(PHOTOGRAPHED.url);
    // Named for a screen reader and for the operator's tooltip: a warehouse
    // row of anonymous thumbnails is a row of guesses.
    expect(imgs[0].getAttribute('alt')).toContain(PHOTOGRAPHED.color);
  });

  it('reserves the space before the picture arrives', async () => {
    // A thumbnail that sizes itself on load moves every row under it, which is
    // how a click lands on the wrong «Списать».
    const page = await render();
    const img = page.all('#stockBody img.thumb')[0] as HTMLImageElement;
    expect(img.getAttribute('width')).toBe('32');
    expect(img.getAttribute('height')).toBe('32');
  });

  it('an unphotographed colour gets a placeholder, not a request that 404s', async () => {
    const page = await render();
    // One <img> for the one photo we hold. GET /shop/products/:id/photo answers
    // 404 for the rest — a normal state, not something to fire and catch.
    expect(page.all('#stockBody img').length).toBe(1);
    const blanks = page.all('#stockBody .thumb.none');
    // Five product rows and the five colours we hold no photo for.
    expect(blanks.length).toBe(10);
    const title = blanks.map((b) => b.getAttribute('title') ?? '').join(' ');
    expect(title, 'a blank that does not say it is blank').toContain('фото не загружено');
    expect(title, 'nowhere to go and fix it').toContain('Каталог');
  });
});

describe('«Хватит на» as a column', () => {
  it('is a column, with the rule under the table', async () => {
    const page = await render();
    const heads = page.all('#stockBody th').map((th) => (th.textContent ?? '').trim());
    expect(heads).toContain('Хватит на');
    expect(heads).toContain('Остаток');
    expect(heads).toContain('В пути');
    expect(heads).toContain('Фото');
    const rule = page.text('#stockRule');
    expect(rule).toContain('продано за 30 дн.');
    expect(rule).toContain('14 дн.');
  });

  it('an empty shelf does not read as «хватит на 0 дн.»', async () => {
    // The owner's whole screen is this case. A zero divided by a rate that
    // does not exist is not a forecast, and printing one is the fastest way to
    // make a buyer stop reading the column.
    const page = await render();
    const cover = page.all('#stockBody td.cover').map((c) => (c.textContent ?? '').replace(/\s+/g, ' ').trim());
    // The sold-out product is the case where the arithmetic really does yield
    // zero — «0 дн.» is what the column prints if it divides anyway. Asserted
    // first, because it is the defect; the wording below is the remedy.
    // A bare zero, not the «30 дн.» window that legitimately ends in one.
    expect(cover.filter((c) => /(?:^|[^0-9])0 дн\./.test(c)), 'a forecast of nothing').toEqual([]);
    const zero = cover.find((c) => c.includes('нет остатка'));
    expect(zero, 'the zero shelf says nothing about being empty').toBeTruthy();
    // …and the urgent fact about an empty shelf is whether anything is coming.
    expect(zero).toContain('в пути 12 шт.');
    expect(cover.some((c) => c.includes('поставок в пути нет'))).toBe(true);
  });

  it('stock with no sales says the rate is unknown, never zero and never ∞', async () => {
    const page = await render();
    const body = page.text('#stockBody');
    const cover = page.all('#stockBody td.cover').map((c) => (c.textContent ?? '').replace(/\s+/g, ' ').trim());
    const idle = cover.find((c) => c.includes('нет продаж'));
    expect(idle, '15 on the shelf and no demand reads as a forecast').toBeTruthy();
    expect(idle).toContain('продаж за 30 дн. не было');
    expect(idle).toContain('скорость неизвестна');
    expect(body).toContain('продаж за 30 дн. не было');
    expect(body).not.toContain('Infinity');
    expect(body).not.toContain('NaN');
    expect(body).not.toContain('undefined');
  });

  it('a figure keeps its denominator after moving into a column', async () => {
    const page = await render();
    const cover = page.all('#stockBody td.cover').map((c) => (c.textContent ?? '').replace(/\s+/g, ' ').trim());
    const fast = cover.find((c) => c.includes('4 дн.'));
    expect(fast).toBeTruthy();
    expect(fast).toContain('6 шт/день');
    expect(fast).toContain('продано 180 шт. за 30 дн.');
    expect(fast).toContain('пора заказывать');
  });

  it('puts what runs out first at the top, and says that it did', async () => {
    const page = await render();
    const names = page.all('#stockBody tr.prow td:nth-child(2) b')
      .map((b) => (b.textContent ?? '').trim());
    const rank = (n: string) => names.findIndex((x) => x.includes(n));
    // Nothing on the shelf outranks four days of cover; four days outranks a
    // product nobody is buying. Unknown goes last rather than being slotted in
    // among the numbers, which would pretend the срок is known.
    expect(rank('Часы')).toBeLessThan(rank('Ремешок'));
    expect(rank('Держатель')).toBeLessThan(rank('Ремешок'));
    expect(rank('Ремешок')).toBeLessThan(rank('Брелок'));
    expect(page.text('#stockRule')).toContain('кончится раньше');
  });

  it('a colour row says the figure is per-product rather than inventing a per-colour rate', async () => {
    // Sales are booked against the product; a runway per colour would be a
    // number this schema cannot answer.
    //
    // It said «—», which was worse than empty: the «В пути» cell beside it uses
    // the same dash for a MEASURED zero, so one grey glyph carried two meanings
    // in one row and the column read as answered where it has no answer. The
    // cell states its own reason now.
    const page = await render();
    const colourCells = page.all('#stockBody tr.crow td:nth-child(5)');
    expect(colourCells.length).toBeGreaterThan(0);
    for (const c of colourCells) {
      expect((c.textContent ?? '').trim(), 'a colour cell that explains nothing').toBe('по товару');
      expect(c.getAttribute('title') ?? '', 'no reason within reach of the cell')
        .toContain('продажи пишутся на товар, а не на цвет');
    }
    // And the same glyph is not doing two jobs in one row: «В пути» keeps the
    // dash, and it is now the only one.
    const inTransit = page.all('#stockBody tr.crow td:nth-child(4)')
      .map((c) => (c.textContent ?? '').trim());
    expect(inTransit).toContain('—');
    expect(page.text('#stockRule')).toContain('«по товару»');
  });
});

/**
 * The amber plate. Every branch of it names WHY a product is on the list —
 * except the threshold one, which named the count and stopped, and the
 * sold-out one, which printed a forecast of zero days.
 */
describe('плашка дефицита', () => {
  it('an empty shelf is not given a forecast of nought days', async () => {
    // «Держатель» sold 90 in the window and is now at zero, so the arithmetic
    // really does yield 0 days of cover. The column refuses to print it; the
    // banner three lines away must not print it either.
    const page = await render();
    const list = page.text('#stockLowList');
    // The defect first, so a failure names it rather than naming the remedy.
    expect(list, 'the banner keeps the number the column threw out')
      .not.toMatch(/(?:^|[^0-9])0 дн\./);
    expect(list).toContain('Держатель — нет на складе');
  });

  it('says which rule put a product on the list, not just how many are left', async () => {
    // «Часы» are there on the hand-set threshold: nothing sold in the window,
    // so the sales rate cannot have flagged them, and a reader who is not told
    // that reads the plate as a judgement about demand.
    const page = await render();
    const list = page.text('#stockLowList');
    expect(list).toContain('Часы Ana-Bala — нет на складе');
    const forThreshold = list.split(' · ').find((s) => s.includes('порог склада'));
    expect(forThreshold, 'the threshold branch still names only a count').toBeTruthy();
    expect(forThreshold).toContain('порог склада 3 шт.');
    // …and why the better rule stayed silent, in the same words the column uses.
    expect(forThreshold).toContain('продаж за 30 дн. не было');
  });
});

describe('движения за день', () => {
  it('asks for the day the operator is in, not the server', async () => {
    const page = await render();
    const req = page.asked.find((p) => p.includes('/admin/inventory/moves') && p.includes('since='));
    expect(req, 'the day block reads the whole ledger and calls it today').toBeTruthy();
    const since = new Date(decodeURIComponent(req!.split('since=')[1]));
    const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
    expect(since.getTime()).toBe(midnight.getTime());
  });

  it('shows what moved, with the author and the reason the card promises', async () => {
    const page = await render();
    const body = page.text('#stockDayBody');
    expect(body).toContain('Приход');
    expect(body).toContain('Списание');
    expect(body).toContain('накладная 118');
    expect(body).toContain('ерен');
    expect(body).toContain('anna');
  });

  it('adds the day up by reason, because a net of zero is not a quiet day', async () => {
    const page = await render();
    const note = page.text('#stockDayNote');
    expect(note).toContain('приход +27 шт.');
    expect(note).toContain('продажа -2 шт.');
    expect(note).toContain('списание -1 шт.');
    expect(note).toContain('3 записи');
  });

  it('refuses to total a truncated day', async () => {
    // The rows shown are a slice of the period; their sum is short, and a short
    // sum looks exactly like a full one.
    const page = await render({ dayExact: false });
    const note = page.text('#stockDayNote');
    expect(note).toContain('итог за день не считаем');
    expect(note).not.toContain('приход +27');
  });

  it('an empty day says it was empty, and a failed read says it failed', async () => {
    const quiet = await render({ dayMoves: [] });
    expect(quiet.text('#stockDayBody')).toContain('Сегодня остатки не двигались');

    const broken = await render({ dayFails: true });
    expect(broken.text('#stockDayBody')).toContain('сбой чтения');
    expect(broken.text('#stockDayBody')).not.toContain('не двигались');
    expect(broken.text('#stockDayNote')).toBe('');
  });
});

describe('what the screen does when it cannot read', () => {
  it('a failed /admin/inventory is not an empty warehouse', async () => {
    // «нет на складе» against every product is this panel's signature bug, and
    // this is the screen that would say it.
    const page = await render({ inventoryFails: true });
    const body = page.text('#stockBody');
    expect(body).toContain('сбой чтения');
    expect(body).not.toContain('нет остатка');
    expect(page.all('#stockBody tr.prow').length).toBe(0);
  });

  it('still reports the day, which is a different request', async () => {
    const page = await render({ inventoryFails: true });
    expect(page.text('#stockDayBody')).toContain('накладная 118');
  });
});

describe('«Списать»', () => {
  it('asks before writing an irreversible row, and writes nothing if refused', async () => {
    const page = await render({ confirmAnswer: false });
    const btn = page.all('#stockBody button.off')[0] as HTMLButtonElement;
    expect(btn, 'no write-off button to guard').toBeTruthy();
    btn.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 60));
    expect(page.posted.filter((x) => x.path.includes('/admin/inventory/moves'))).toHaveLength(0);
  });

  it('books the write-off with its reason once it is confirmed', async () => {
    const page = await render({ confirmAnswer: true });
    const btn = page.all('#stockBody button.off')[0] as HTMLButtonElement;
    btn.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 60));
    const sent = page.posted.find((x) => x.path.includes('/admin/inventory/moves'));
    expect(sent, 'a confirmed write-off that never reached the server').toBeTruthy();
    expect(sent!.body).toMatchObject({ delta: -1, reason: 'writeoff', note: 'брак' });
  });
});
