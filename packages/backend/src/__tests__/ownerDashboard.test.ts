/**
 * Frame 00 — «Дашборд владельца».
 *
 * The money on this screen decides whether stock gets bought, so the tests that
 * matter are the ones about what it refuses to claim: revenue that has not left
 * the building, a profit computed over costs nobody recorded, a plan percentage
 * with no plan behind it, and a «Решение недели» invented because the card was
 * empty.
 */

import { describe, it, expect } from 'vitest';
import {
  buildOwnerDashboard, decisionOfTheWeek, whatBurns,
  type OwnerInput,
} from '../admin/ownerDashboard';
import type { InventoryProduct, ShopOrder } from '../db/repository';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { StaffRole } from '../auth/capabilities';

const NOW = new Date('2026-08-08T12:00:00.000Z');
const daysAgo = (d: number) => new Date(NOW.getTime() - d * 86_400_000).toISOString();

const order = (o: Partial<ShopOrder> = {}): ShopOrder => ({
  id: 'o' + Math.round(Math.random() * 1e9),
  customerName: 'Айгерім', phone: '+77000000000', city: 'Алматы', address: 'ул. 1',
  note: null, totalMinor: 3_900_000, discountMinor: 0,
  status: 'delivered', createdAt: daysAgo(2),
  items: [{ productName: 'Комплект', color: 'rose', qty: 1, unitPriceMinor: 3_900_000 }],
  ...o,
});

const product = (p: Partial<InventoryProduct> = {}): InventoryProduct => ({
  id: 'p1', name: 'Комплект', sku: null, priceMinor: 3_900_000, costMinor: 2_400_000,
  kind: 'simple', active: true, sort: 0, lowStockThreshold: 3, stock: 10, lowStock: false,
  variants: [],
  ...p,
});

const QUIET: OwnerInput['signals'] = {
  overdue: [], lowStock: [], unreviewedMedical: 0,
  unregisteredDevices: 0, accessWithoutReason: 0, courseNeverStarted: 0,
};

const build = (over: Partial<OwnerInput> = {}) =>
  buildOwnerDashboard(
    { orders: [], products: [], planMinor: null, signals: QUIET, ...over },
    NOW,
  );

describe('the money', () => {
  it('counts only what left the building', () => {
    // A confirmed order is a promise. Counting it as revenue is how a month
    // looks fine until the cancellations land.
    const d = build({
      orders: [
        order({ status: 'delivered', totalMinor: 100 }),
        order({ status: 'shipped', totalMinor: 200 }),
        order({ status: 'confirmed', totalMinor: 4000 }),
        order({ status: 'new', totalMinor: 8000 }),
        order({ status: 'cancelled', totalMinor: 9999 }),
      ],
    });
    expect(d.money.revenueMinor).toBe(300);
    expect(d.money.orders).toBe(2);
    // The promised money is not lost — it is the other half of the cash gap.
    expect(d.money.pipelineMinor).toBe(12_000);
  });

  it('ignores revenue from before this month', () => {
    const d = build({
      orders: [
        order({ totalMinor: 500, createdAt: '2026-08-01T00:00:00.000Z' }),
        order({ totalMinor: 700, createdAt: '2026-07-31T23:59:59.000Z' }),
      ],
    });
    expect(d.money.revenueMinor).toBe(500);
  });

  it('subtracts what the goods cost us', () => {
    const d = build({ orders: [order()], products: [product()] });
    expect(d.money.netProfitMinor).toBe(3_900_000 - 2_400_000);
    expect(d.money.costCoverage).toBe(1);
  });

  it('says how much of the revenue had a cost behind it', () => {
    // This is the number that decides whether the profit above may be read as
    // a fact. Half the catalogue costed means half a profit figure.
    const d = build({
      orders: [
        order({
          totalMinor: 1000,
          items: [{ productName: 'Комплект', color: 'rose', qty: 1, unitPriceMinor: 1000 }],
        }),
        order({
          totalMinor: 1000,
          items: [{ productName: 'Часы', color: 'black', qty: 1, unitPriceMinor: 1000 }],
        }),
      ],
      products: [product({ costMinor: 400 })],
    });
    expect(d.money.costCoverage).toBe(0.5);
    // Only the costed half is subtracted — the uncosted line is not assumed free.
    expect(d.money.netProfitMinor).toBe(2000 - 400);
  });

  it('reports no plan as null, not as nought per cent', () => {
    // 0 % renders as a failed month. "Nobody set a target" is a different fact
    // and the screen has to be able to say it.
    expect(build({ orders: [order()] }).money.planPct).toBeNull();
    expect(build({ orders: [order()], planMinor: 0 }).money.planPct).toBeNull();
  });

  it('measures the plan when there is one', () => {
    const d = build({ orders: [order({ totalMinor: 500 })], planMinor: 2000 });
    expect(d.money.planPct).toBe(0.25);
  });

  it('values the shelf at cost, not at the price on the label', () => {
    // Money in stock is cash already spent. Valuing it at retail books a profit
    // on goods nobody has bought.
    const d = build({ products: [product({ stock: 3, costMinor: 100, priceMinor: 999 })] });
    expect(d.money.moneyInStockMinor).toBe(300);
  });

  it('does not double-count a bundle against its parts', () => {
    // A bundle's stock is derived from the parts it is assembled from, so
    // adding both counts the same physical box twice.
    const d = build({
      products: [
        product({ id: 'p1', name: 'Часы', stock: 4, costMinor: 100, kind: 'simple' }),
        product({ id: 'p2', name: 'Комплект', stock: 4, costMinor: 250, kind: 'bundle' }),
      ],
    });
    expect(d.money.moneyInStockMinor).toBe(400);
  });

  it('reads the cash gap as stock sunk minus money on its way in', () => {
    const d = build({
      products: [product({ stock: 10, costMinor: 100 })],
      orders: [order({ status: 'new', totalMinor: 400 })],
    });
    expect(d.money.cashGapMinor).toBe(1000 - 400);
  });
});

describe('the fourteen-day chart', () => {
  it('has fourteen days, oldest first, ending today', () => {
    const d = build();
    expect(d.revenue14d).toHaveLength(14);
    expect(d.revenue14d[13].day).toBe('2026-08-08');
    expect(d.revenue14d[0].day).toBe('2026-07-26');
  });

  it('keeps the days with no sales', () => {
    // Dropping them draws a chart that hides exactly what it is read for.
    const d = build({ orders: [order({ totalMinor: 700, createdAt: daysAgo(3) })] });
    const empty = d.revenue14d.filter((r) => r.revenueMinor === 0);
    expect(empty).toHaveLength(13);
    expect(d.revenue14d.find((r) => r.day === '2026-08-05')?.revenueMinor).toBe(700);
  });

  it('leaves unearned orders off it', () => {
    const d = build({ orders: [order({ status: 'new', totalMinor: 700, createdAt: daysAgo(3) })] });
    expect(d.revenue14d.every((r) => r.revenueMinor === 0)).toBe(true);
  });
});

describe('«Откуда выручка»', () => {
  it('ranks the products and shares out to one', () => {
    const d = build({
      orders: [
        order({ totalMinor: 300, items: [{ productName: 'Часы', color: 'b', qty: 1, unitPriceMinor: 300 }] }),
        order({ totalMinor: 700, items: [{ productName: 'Комплект', color: 'r', qty: 1, unitPriceMinor: 700 }] }),
      ],
    });
    expect(d.sources[0].product).toBe('Комплект');
    expect(d.sources[0].share).toBeCloseTo(0.7, 6);
    expect(d.sources.reduce((s, x) => s + x.share, 0)).toBeCloseTo(1, 6);
  });

  it('counts units, not just money', () => {
    const d = build({
      orders: [order({ items: [{ productName: 'Часы', color: 'b', qty: 3, unitPriceMinor: 100 }] })],
    });
    expect(d.sources[0].units).toBe(3);
    expect(d.sources[0].revenueMinor).toBe(300);
  });
});

describe('«Что горит»', () => {
  it('is empty when nothing is', () => {
    // A permanently populated list is one nobody reads.
    expect(whatBurns(QUIET)).toEqual([]);
  });

  it('puts a person waiting above a shelf running low', () => {
    const b = whatBurns({ ...QUIET, lowStock: ['p1'], overdue: ['emergencies'] });
    expect(b[0].key).toBe('overdue');
    expect(b[0].level).toBe('crit');
    expect(b.find((x) => x.key === 'low_stock')?.level).toBe('warn');
  });

  it('treats unsigned medical advice and unexplained access as critical', () => {
    const b = whatBurns({ ...QUIET, unreviewedMedical: 2, accessWithoutReason: 1 });
    expect(b.map((x) => x.level)).toEqual(['crit', 'crit']);
    expect(b[0].count).toBe(2);
  });
});

describe('«Решение недели»', () => {
  const ctx = (over: Partial<Parameters<typeof decisionOfTheWeek>[0]> = {}) =>
    decisionOfTheWeek({
      signals: QUIET, revenueMinor: 1000, planMinor: 1000, costCoverage: 1, sources: [],
      ...over,
    });

  it('says nothing when there is nothing to decide', () => {
    // A card that manufactures a decision every week teaches its reader to
    // ignore it, and then it is useless on the week it matters.
    expect(ctx()).toBeNull();
  });

  it('always offers three ways out', () => {
    // Two options is a yes/no in disguise, which is not a decision to think
    // about — it is one already made by whoever wrote the card.
    for (const c of [
      ctx({ signals: { ...QUIET, unreviewedMedical: 1 } }),
      ctx({ revenueMinor: 100, planMinor: 1000 }),
      ctx({ signals: { ...QUIET, courseNeverStarted: 5 } }),
      ctx({ costCoverage: 0.2 }),
    ]) {
      expect(c).not.toBeNull();
      expect(c!.options).toHaveLength(3);
      expect(c!.because.length).toBeGreaterThan(10);
    }
  });

  it('puts unsigned medical advice above a missed plan', () => {
    // Money is not the most urgent thing on the screen, and the ordering is
    // where that belief either exists or does not.
    const c = ctx({ signals: { ...QUIET, unreviewedMedical: 3 }, revenueMinor: 0, planMinor: 1000 });
    expect(c!.key).toBe('medical_review');
  });

  it('quotes the number that raised it', () => {
    const c = ctx({ signals: { ...QUIET, unreviewedMedical: 3 } });
    expect(c!.because).toContain('3');
  });

  it('names what is already selling when the plan is missed', () => {
    const c = ctx({
      revenueMinor: 100, planMinor: 1000,
      sources: [{ product: 'Комплект', revenueMinor: 100, units: 1, share: 1 }],
    });
    expect(c!.key).toBe('behind_plan');
    expect(c!.because).toContain('Комплект');
  });

  it('does not raise a plan it was never given', () => {
    // Without a target, "behind plan" is an opinion.
    expect(ctx({ revenueMinor: 0, planMinor: null })).toBeNull();
  });

  it('mentions unreliable costs only when nothing worse is wrong', () => {
    expect(ctx({ costCoverage: 0.2 })!.key).toBe('cost_coverage');
    expect(ctx({ costCoverage: 0.2, signals: { ...QUIET, courseNeverStarted: 2 } })!.key)
      .toBe('course_unused');
  });
});

// ---------------------------------------------------------------------------

describe('GET /admin/owner', () => {
  function makeApp(role: StaffRole) {
    return buildServer(
      {
        repo: createMemoryRepository(),
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => ({ userId: DEMO_USER }),
        authAdmin: async () => ({ staffId: 's1', role }),
      },
      { logger: false },
    );
  }

  it('answers with every row of the frame', async () => {
    // Driven over HTTP against the real repository, because the failure that
    // actually happens is a module that computes perfectly and a route that
    // never reaches it.
    const app = makeApp('owner');
    const r = await app.inject({ method: 'GET', url: '/admin/owner' });
    expect(r.statusCode).toBe(200);
    const b = r.json();
    expect(b.money).toBeTruthy();
    expect(b.revenue14d).toHaveLength(14);
    expect(Array.isArray(b.sources)).toBe(true);
    expect(Array.isArray(b.burning)).toBe(true);
    // `decision` may legitimately be null; the KEY must exist so the panel can
    // tell "nothing to decide" from "the server never sent the field".
    expect('decision' in b).toBe(true);
    expect(b.who).toBeTruthy();
    await app.close();
  });

  it('takes the plan from settings and reports none when unset', async () => {
    const app = makeApp('owner');
    expect((await app.inject({ method: 'GET', url: '/admin/owner' })).json().money.planPct)
      .toBeNull();

    await app.inject({
      method: 'PUT', url: '/admin/settings',
      payload: { revenuePlanMinor: '5000000' },
    });
    const b = (await app.inject({ method: 'GET', url: '/admin/owner' })).json();
    expect(b.money.planMinor).toBe(5_000_000);
    await app.close();
  });

  it('is finance, so a seller cannot read the margin', async () => {
    // «заказы, витрина, остатки, контакты — без маржи и без детей».
    const seller = makeApp('seller');
    expect((await seller.inject({ method: 'GET', url: '/admin/owner' })).statusCode).toBe(403);
    await seller.close();
  });
});
