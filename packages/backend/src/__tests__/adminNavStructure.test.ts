/**
 * The sidebar is seven sections. Not twenty-seven buttons.
 *
 * «Структура меню — ровно семь разделов» (docs/CLAUDE-admin-design.md §3.2) is
 * the one structural rule the spec calls non-negotiable, and the panel ignored
 * it: twenty-seven flat rows in a rail that scrolled itself, so «Роли и права»,
 * «Лендинг» and «API-сервис» sat permanently below the fold and nothing said
 * which of the twenty-seven belonged together. The owner's complaint was that
 * the STRUCTURE did not match the design, and he was right.
 *
 * Rendered in jsdom rather than read as source, because the thing being
 * asserted — which sub-items are on screen under which section — is a runtime
 * state that go() and applyCaps compute. "Verified structurally" would have
 * passed against a rail that never expands.
 *
 * Every check here fails if the rail goes back to a flat list.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * Six fixed sleeps — 300 after boot, 60–150 after each rail click — decided
 * their verdict on elapsed wall-clock rather than on the work being finished.
 * The rail is drawn by applyCaps AFTER /admin/me answers, and the badges by the
 * loaders that follow it, so a window that closed early read a rail with no
 * capabilities applied: every section visible, which is what most of these
 * assertions are looking for.
 *
 * They are all quiet() now: no request in flight, none newly issued for several
 * consecutive turns, no page timer outstanding, and a throw rather than a
 * half-drawn screen. See helpers/panelSettle.ts.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle } from './helpers/panelSettle';
import type { StaffRole } from '../auth/capabilities';
import { buildFinanceReport } from '../admin/finance';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** The seven, in the order the artifact draws them. */
const SECTIONS = ['Обзор', 'Экстренные', 'Продажи', 'Склад', 'Пользователи', 'Контент', 'Настройки'];

/**
 * Every screen the panel could reach before the rail was regrouped.
 *
 * Enumerated by hand on purpose: reading it back out of the same markup would
 * pass whatever the markup happened to say. `safety` is in the list — it lost
 * its tab, not its reachability, and #safety still has to land on the screen
 * that holds its table.
 */
const VIEWS_BEFORE = [
  'overview', 'owner', 'emergencies', 'users', 'content', 'review', 'kids',
  'antenatal', 'pregweeks', 'childdev', 'vaccines', 'devices', 'safety',
  'course', 'catalog', 'stock', 'shop', 'marketing', 'audio', 'analytics',
  'audit', 'staff', 'finance', 'support', 'integrations', 'security', 'roles',
];

/**
 * Screens added to the rail SINCE that snapshot.
 *
 * The check below says "nothing was invented on the way", which is about the
 * regrouping, not about the panel never growing again. Listing a new view here
 * is a deliberate act with a name attached; leaving the list out and relaxing
 * the assertion to "anything goes" would retire the guard entirely.
 */
const VIEWS_ADDED_SINCE = [
  // Кадр 16b «Экстренная помощь» → экран приложения 37.
  'emergency-help',
  // Кадр 17c «Детектор плача» — внутри «Контента», рядом с вакцинацией.
  'cry',
  // Кадр 25 «Уведомления» — внутри «Настроек», рядом с интеграциями: это
  // состояние доставки, а не редактор сообщений.
  'notifications',
];

const FINANCE = buildFinanceReport({
  orders: [], products: [], moves: [], planMinor: 0, from: '2026-08-01', to: '2026-08-31',
});

async function openAs(role: StaffRole = 'owner', hash = '') {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const vc = new VirtualConsole();
  const errors: string[] = [];
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: `http://localhost/admin/ui${hash}`,
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
      (window as unknown as { alert: (m: string) => void }).alert = () => {};
      settle.attach(window as never, async (path: string) => {
        const p = path;
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role, displayName: 'Ерен' }) };
        }
        // Empty-but-shaped. This file is about the rail, not about any list —
        // but a loader that throws on a shape it did not expect would surface
        // here as an unhandled rejection and make every assertion suspect.
        const body: Record<string, unknown> = {
          devices: [], products: [], moves: [], orders: [], leads: [], variants: [],
          events: [], emergencies: [], users: [], audit: [], items: [], stages: {}, settings: {},
        };
        if (p.includes('/admin/shop/products')) body.stages = [];
        // One order nobody has touched. It is what puts a count on «Заказы»,
        // which is how the roll-up onto a closed «Продажи» gets tested.
        if (p.includes('/admin/shop/orders')) {
          body.orders = [{
            id: 'o1', customerName: 'Айгерім', phone: '+77001112233', city: 'Алматы',
            address: 'ул. Абая 1', note: null, totalMinor: 100_000, discountMinor: 0,
            status: 'new', createdAt: '2026-08-10T10:00:00.000Z', items: [],
          }];
        }
        // The real report over no data, rather than a hand-written shape: a
        // drifted fixture would report a bug in a working panel.
        const answer = p.includes('/admin/finance') ? FINANCE : body;
        return { ok: true, status: 200, text: async () => '', json: async () => answer };
      });
    },
  });

  await settle.quiet('boot');
  return { window: dom.window, errors, quiet: settle.quiet };
}

const text = (el: Element | null) => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();

/** The section rows a person can actually see. */
const sections = (w: JSDOM['window']) =>
  [...w.document.querySelectorAll('.navgroup:not([hidden]) .navsec')]
    .map((el) => text(el.querySelector('.secname')));

/** The sub-items on screen — only the open section has any. */
const openItems = (w: JSDOM['window']) =>
  [...w.document.querySelectorAll('.navsub:not([hidden]) .nav.sub:not([hidden])')] as HTMLElement[];

describe('the sidebar has exactly seven sections', () => {
  it('seven top-level rows, named and ordered as the artifact draws them', async () => {
    const { window, errors } = await openAs('owner');
    expect(errors, errors.join('\n')).toEqual([]);
    expect(sections(window)).toEqual(SECTIONS);
  });

  it('nothing else sits at the top level of the rail', async () => {
    // The failure this catches is a regression to the flat list: a new tab
    // added as a twenty-eighth sibling instead of into a section. Every
    // navigable item is either one of the seven or a sub-item of one.
    const { window } = await openAs('owner');
    const stray = [...window.document.querySelectorAll('#navTree .nav[data-view]')]
      .filter((el) => !el.classList.contains('navsec') && !el.parentElement?.classList.contains('navsub'))
      .map((el) => (el as HTMLElement).dataset.view);
    expect(stray, `these hang off the rail with no section: ${stray.join(', ')}`).toEqual([]);
    expect(window.document.querySelectorAll('#navTree > .navgroup').length).toBe(7);
  });

  it('sub-items are listed only under the open section', async () => {
    const { window, quiet } = await openAs('owner');
    // Frame 00: Обзор open, its three underneath, everything else a plain row.
    expect(openItems(window).map((el) => text(el))).toEqual(['Сводка', 'Дашборд владельца', 'Аналитика']);
    const open = [...window.document.querySelectorAll('.navsub:not([hidden])')];
    expect(open.length, 'two sections were expanded at once').toBe(1);

    // Move to a different section: the first one closes behind you.
    const people = window.document.querySelector('.navgroup[data-section="people"] .navsec') as HTMLElement;
    people.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the Пользователи section');
    expect(openItems(window).map((el) => text(el).split(' ')[0]))
      .toEqual(['Мамы', 'Дети', 'Устройства', 'Поддержка']);
    expect(window.document.querySelectorAll('.navsub:not([hidden])').length).toBe(1);
    expect(text(window.document.querySelector('#pageTitle'))).toBe('Пользователи');
    expect(window.location.hash).toBe('#users');
  });

  it('the open section is the white plate, and it says so to a screen reader', async () => {
    const { window } = await openAs('owner');
    const overview = window.document.querySelector('.navgroup[data-section="overview"] .navsec')!;
    expect(overview.classList.contains('active')).toBe(true);
    expect(overview.getAttribute('aria-expanded')).toBe('true');
    const sales = window.document.querySelector('.navgroup[data-section="sales"] .navsec')!;
    expect(sales.classList.contains('active')).toBe(false);
    expect(sales.getAttribute('aria-expanded')).toBe('false');
  });

  it('a count on a folded-away sub-item rolls up onto its section', async () => {
    // «Заказы» lives inside «Продажи». An order waiting behind a closed section
    // with nothing on the section row is a count nobody can see, which is worse
    // than no count at all.
    const { window, quiet } = await openAs('owner');
    const shop = window.document.querySelector('.nav[data-anchor="shopOrdersCard"]') as HTMLElement;
    shop.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the Заказы card');
    const badge = window.document.getElementById('shopBadge') as HTMLElement;
    expect(badge.hidden, 'the waiting order never reached its own badge').toBe(false);
    expect(badge.textContent).toBe('1');
    const sum = window.document.querySelector('.navgroup[data-section="sales"] .badge.sum') as HTMLElement;
    // Открытый раздел: счётчики стоят на подпунктах, на самой строке раздела их нет.
    expect(sum.hidden, 'an open section double-counts its own children').toBe(true);

    // Close it by going elsewhere; now the section has to carry the number.
    (window.document.querySelector('.navgroup[data-section="overview"] .navsec') as HTMLElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the Обзор section');
    expect(sum.hidden, 'a closed section dropped the count of what is waiting inside it').toBe(false);
    expect(sum.textContent).toBe('1');

    // And it keeps up without a navigation: the live refresh re-counts orders
    // while the operator is standing on another screen, and a section row that
    // only recomputes on a click would sit there saying yesterday's number.
    (window as unknown as { UI: { setBadge(el: Element | null, n: number): void } })
      .UI.setBadge(window.document.getElementById('shopBadge'), 4);
    expect(sum.textContent, 'the section count did not follow a live update').toBe('4');
  });

  it('«Экстренные» has no sub-items and carries its count', async () => {
    const { window } = await openAs('owner');
    const g = window.document.querySelector('.navgroup[data-section="emergencies"]')!;
    expect(g.querySelector('.navsub'), 'Экстренные grew sub-items the artifact does not show').toBeNull();
    expect(g.querySelector('.navsec')!.classList.contains('nav')).toBe(true);
    expect((g.querySelector('.navsec') as HTMLElement).dataset.view).toBe('emergencies');
    expect(g.querySelector('#navBadge'), 'the count is gone').not.toBeNull();
  });
});

describe('everything that was reachable is still reachable', () => {
  it('every view the flat rail could open has a home in a section', async () => {
    const { window } = await openAs('owner');
    const inRail = new Set(
      [...window.document.querySelectorAll('#navTree .nav[data-view]')]
        .map((el) => (el as HTMLElement).dataset.view!),
    );
    // safety is the one exception, and it is deliberate: it is a card on the
    // Экстренные screen now, reached through the alias below.
    const missing = VIEWS_BEFORE.filter((v) => v !== 'safety' && !inRail.has(v));
    expect(missing, `dropped on the way into the sections: ${missing.join(', ')}`).toEqual([]);

    // And nothing was invented on the way.
    const extra = [...inRail].filter(
      (v) => !VIEWS_BEFORE.includes(v) && !VIEWS_ADDED_SINCE.includes(v));
    expect(extra, `these views appeared from nowhere: ${extra.join(', ')}`).toEqual([]);
  });

  it('every sub-item points at a section of the page that exists', async () => {
    const { window } = await openAs('owner');
    for (const el of window.document.querySelectorAll('#navTree .nav[data-view]')) {
      const view = (el as HTMLElement).dataset.view!;
      expect(window.document.getElementById(view), `${view} has no section`).not.toBeNull();
      const anchor = (el as HTMLElement).dataset.anchor;
      if (anchor) expect(window.document.getElementById(anchor), `${anchor} is not on the page`).not.toBeNull();
    }
  });

  it('a bookmarked #finance still opens Финансы, inside Продажи', async () => {
    const { window, errors } = await openAs('owner', '#finance');
    expect(errors, errors.join('\n')).toEqual([]);
    expect(text(window.document.querySelector('#pageTitle'))).toBe('Финансы');
    expect(window.document.querySelector('#finance')!.classList.contains('active')).toBe(true);
    expect(openItems(window).map((el) => text(el)))
      .toEqual(['Заказы', 'Витрина и заявки', 'Финансы', 'Маркетинг']);
    expect(text(window.document.querySelector('.nav.active'))).toBe('Финансы');
  });

  it('a bookmarked #safety lands on the screen that holds its table', async () => {
    const { window } = await openAs('owner', '#safety');
    expect(text(window.document.querySelector('#pageTitle'))).toBe('Экстренные');
    expect(window.document.querySelector('#emergencies #safetyBody'), 'the SOS table moved out from under the alias')
      .not.toBeNull();
  });

  it('two sub-items on the same screen light up separately', async () => {
    // Остатки and Приёмка are two cards on #stock. Marking both current would
    // make the rail lie about where you are.
    const { window, quiet } = await openAs('owner');
    const receive = window.document.querySelector('.nav[data-anchor="stockReceiveCard"]') as HTMLElement;
    receive.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the Приёмка card');
    const active = [...window.document.querySelectorAll('.nav.active')].map((el) => text(el));
    expect(active).toEqual(['Приёмка']);
    expect(window.location.hash, 'an anchor must not invent a route').toBe('#stock');
  });
});

describe('the rail shows a person only what she can open', () => {
  it('a warehouse hand gets the sections she works in, not six greyed rows', async () => {
    const { window, errors } = await openAs('warehouse');
    expect(errors, errors.join('\n')).toEqual([]);
    const visible = sections(window);
    expect(visible, 'a section with nothing in it for her is still drawn').not.toContain('Экстренные');
    expect(visible).not.toContain('Пользователи');
    expect(visible).toContain('Склад');

    // «Настройки» IS drawn for her, and the rule has not changed: a section is
    // drawn when it holds something she can open, and this one now does.
    //
    // «Персонал» lost its data-cap. The tab holds her own password form, which
    // /admin/staff/me/password lets ANY signed-in role use — hiding the tab
    // hid the form with it, so a warehouse hand whose password had leaked
    // could not rotate it. The roster inside carries `staff` instead.
    //
    // Asserted as an exact list rather than relaxed to "may contain": the
    // section must hold that one item and nothing else, or the capability has
    // leaked somewhere new.
    expect(visible).toContain('Настройки');
    const settingsGroup = window.document.querySelector('.navgroup[data-section="settings"]') as HTMLElement;
    const openable = [...settingsGroup.querySelectorAll('.nav[data-view]')]
      .filter((el) => !(el as HTMLElement).hidden)
      .map((el) => text(el));
    expect(openable, 'only her own password belongs to her in Настройки').toEqual(['Персонал']);
    expect(
      (window.document.getElementById('staffAdminCard') as HTMLElement).hidden,
      'the colleague roster is `staff` and must stay shut',
    ).toBe(true);

    // And what she lands on is a real screen, not a blank one.
    const active = window.document.querySelector('.nav.active') as HTMLElement;
    expect(active.hidden).toBe(false);
    expect(window.document.getElementById(active.dataset.view!)!.classList.contains('active')).toBe(true);
  });

  it('a content editor opening Склад gets Каталог, the only part of it she has', async () => {
    const { window, quiet } = await openAs('content');
    const wh = window.document.querySelector('.navgroup[data-section="warehouse"]') as HTMLElement;
    expect(wh.hidden, 'Каталог lives in Склад — hiding the section would strand it').toBe(false);
    (wh.querySelector('.navsec') as HTMLElement).dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the Склад section');
    expect(openItems(window).map((el) => text(el).split(' ')[0])).toEqual(['Каталог']);
    expect(text(window.document.querySelector('#pageTitle'))).toBe('Каталог');
  });
});

describe('the rail carries what the artifact puts at its foot', () => {
  it('the two external links, below the sections and above the person', async () => {
    const { window } = await openAs('owner');
    const links = [...window.document.querySelectorAll('.navext a')] as HTMLAnchorElement[];
    expect(links.map((a) => text(a).replace('↗', '').trim())).toEqual(['Лендинг', 'API-сервис']);
    expect(links.map((a) => a.getAttribute('href'))).toEqual(['/', '/api-docs']);
    // They are destinations, not screens: a data-view here would put them in
    // the routing and paint an empty tab.
    expect(links.some((a) => a.hasAttribute('data-view'))).toBe(false);
  });

  it('who is signed in sits in the sidebar, not as a raw role key in the topbar', async () => {
    const { window } = await openAs('owner');
    expect(window.document.querySelector('.sideme #staffName'), 'identity is not in the rail').not.toBeNull();
    expect(text(window.document.querySelector('.sideme #staffName'))).toBe('Ерен');
    expect(text(window.document.querySelector('.sideme #staffRole'))).toBe('владелец');
    expect(window.document.querySelector('.top .chip'), 'the old identity chip is still in the topbar').toBeNull();
  });
});
