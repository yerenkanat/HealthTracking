/**
 * Frame 09a — the mother's card, over HTTP.
 *
 * The unit tests next door prove buildMotherCard's arithmetic. They cannot
 * prove the JOIN, which is where this feature actually lives and where it was
 * broken by default: an order carries the number as somebody read it out over
 * WhatsApp — «+7 (701) 555-11-22» — while the entitlement and the course rows
 * are stored under the normalised «77015551122» the app signs in with. Match
 * the raw strings and the card is empty for a woman with a charge on her card,
 * every unit test in the file still green.
 *
 * So this goes through the front door: stock the shelf, take the order at the
 * spoken number, ship it, and then read the card the operator reads.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import { PRODUCT_STAGES, type Repository } from '../db/repository';
import type { MotherCard } from '../admin/motherCard';

/** Reading someone's record needs a stated reason; it goes in the audit log. */
const WHY = '?reason=' + encodeURIComponent('Обращение клиента');

/**
 * The number as staff type it from a phone call.
 *
 * DIALLED is the number the demo account was CREATED with, not one this test
 * sets: the phone is the sign-in credential and [ProfileEdit] deliberately
 * cannot carry one, so a profile write can no longer claim a number. Which is
 * the point — the card has to find her orders by the number her account
 * already holds, matched against whatever form somebody typed into the shop.
 */
const DIALLED = '+77001112233';
/** The same number, as it arrives from WhatsApp or the landing page. */
const SPOKEN = '+7 (700) 111-22-33';

let repo: Repository;
let app: FastifyInstance;

/** The server the panel talks to, optionally with one repository method broken. */
function serve(r: Repository): FastifyInstance {
  return buildServer(
    {
      repo: r,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role: 'admin' }),
    },
    { logger: false },
  );
}

beforeEach(async () => {
  repo = createMemoryRepository();
  app = serve(repo);
  await app.ready();
  await setProfile({});
});

async function setProfile(patch: Record<string, unknown>): Promise<void> {
  await repo.upsertProfile(DEMO_USER, {
    displayName: 'Айгерим',
    dueDate: null,
    locale: 'ru-KZ',
    birthDate: null,
    city: 'Алматы',
    doctorPhone: null,
    avgCycleLength: null,
    avgPeriodLength: null,
    ...patch,
  } as never);
}

/** Put stock on the shelf through the panel, as staff would. */
async function stock(productId: string, qty: number): Promise<string> {
  const p = (await repo.adminProducts()).find((x) => x.id === productId)!;
  const variantId = p.variants[0].id;
  const res = await app.inject({
    method: 'POST', url: '/admin/inventory/moves',
    payload: { variantId, delta: qty, reason: 'receipt' },
  });
  expect(res.statusCode).toBe(200);
  return variantId;
}

/** Take an order at the desk, at the number as it was read out. */
async function placeOrder(payload: Record<string, unknown>): Promise<string> {
  const res = await app.inject({
    method: 'POST', url: '/admin/shop/orders',
    payload: { customerName: 'Айгерим', phone: SPOKEN, city: 'Астана', address: 'пр. Абая 1', ...payload },
  });
  expect(res.statusCode, res.body).toBe(201);
  return res.json().id as string;
}

async function setStatus(id: string, status: string): Promise<void> {
  const res = await app.inject({ method: 'PATCH', url: `/admin/shop/orders/${id}`, payload: { status } });
  expect(res.statusCode, res.body).toBe(200);
}

/** The card's right-hand column, as the operator opens it. */
async function card(): Promise<MotherCard> {
  const res = await app.inject({ method: 'GET', url: `/admin/users/${DEMO_USER}/detail${WHY}` });
  expect(res.statusCode, res.body).toBe(200);
  const body = res.json() as { mother?: MotherCard };
  expect(body.mother, 'the card carries no mother block at all').toBeTruthy();
  return body.mother!;
}

/** The комплект: both devices in one order, priced as the bundle. */
async function buyTheCombo(): Promise<string> {
  const w = await stock('watch', 5);
  const t = await stock('tracker', 5);
  return placeOrder({ bundleId: 'combo', items: [{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }] });
}

describe('the mother card reaches the drilldown at all', () => {
  it('is on the same response the card already fetched', async () => {
    // One request, not a second one the drawer would have to make: the card
    // opens on a single audited read and this rides along with it.
    const m = await card();
    expect(m).toHaveProperty('stage');
    expect(m).toHaveProperty('orders');
    expect(m).toHaveProperty('course');
  });

  it('speaks the product vocabulary for the stage, with its working', async () => {
    const m = await card();
    expect(PRODUCT_STAGES as readonly string[]).toContain(m.stage);
    expect(m.stageReason.length).toBeGreaterThan(0);
  });

  it('derives pregnancy from the due date on her profile', async () => {
    const due = new Date(Date.now() + 60 * 86400000).toISOString().slice(0, 10);
    await setProfile({ dueDate: due });
    const m = await card();
    expect(m.stage).toBe('pregnancy');
    expect(m.stageReason).toContain(due);
  });

  it('still answers 404 for somebody who does not exist', async () => {
    const res = await app.inject({
      method: 'GET', url: `/admin/users/00000000-0000-0000-0000-000000000000/detail${WHY}`,
    });
    expect(res.statusCode).toBe(404);
  });

  it('still refuses to be read without a reason', async () => {
    // The new block is more of her life on one screen, so the audited gate in
    // front of it matters more, not less.
    const res = await app.inject({ method: 'GET', url: `/admin/users/${DEMO_USER}/detail` });
    expect(res.statusCode).toBe(400);
  });
});

describe('«где мой заказ», answered without leaving the card', () => {
  it('finds an order taken at the spoken form of her number', async () => {
    // THE join. The order holds «+7 (701) 555-11-22»; her profile holds
    // «+77015551122». One number, two spellings.
    await buyTheCombo();
    const m = await card();
    expect(m.orders.total).toBe(1);
    expect(m.orders.open).toBe(1);
    expect(m.orders.lastStatus).toBe('new');
    // What was in the box, so the operator never has to ask "which order?"
    expect(m.orders.recent[0].items.length).toBeGreaterThan(0);
  });

  it('follows the order as its status moves', async () => {
    const id = await buyTheCombo();
    await setStatus(id, 'shipped');
    let m = await card();
    expect(m.orders.lastStatus).toBe('shipped');
    expect(m.orders.open).toBe(1);

    await setStatus(id, 'delivered');
    m = await card();
    expect(m.orders.lastStatus).toBe('delivered');
    expect(m.orders.open, 'delivered is not still owed to her').toBe(0);
  });

  it('does not count a cancelled order as money she spent', async () => {
    const kept = await buyTheCombo();
    const w = await stock('watch', 5);
    const dropped = await placeOrder({ items: [{ variantId: w, qty: 1 }] });
    await setStatus(kept, 'delivered');
    await setStatus(dropped, 'cancelled');

    const m = await card();
    expect(m.orders.total, 'both orders are hers').toBe(2);
    expect(m.orders.spentMinor, 'the комплект only — 39 000 ₸').toBe(3900000);
    // Still listed, though: «он был отменён» is an answer to «где мой заказ».
    expect(m.orders.recent.find((r) => r.id === dropped)?.status).toBe('cancelled');
  });

  it('says she has none rather than showing an empty block', async () => {
    const m = await card();
    expect(m.orders.total).toBe(0);
    expect(m.orders.recent).toEqual([]);
  });

  it("does not hand her somebody else's orders", async () => {
    const w = await stock('watch', 5);
    await placeOrder({ phone: '+7 (777) 000-00-00', items: [{ variantId: w, qty: 1 }] });
    const m = await card();
    expect(m.orders.total).toBe(0);
  });

  it('finds nothing, and does not fall over, for an account with no phone', async () => {
    // No longer reachable through the profile — the phone is the sign-in
    // credential — so the account itself is the one with nothing on it. She
    // owns nothing we can find, which is a real answer, not a crash.
    const detail = await repo.adminUserDetail(DEMO_USER);
    const app2 = serve({ ...repo, adminUserDetail: async () => ({ ...detail!, phone: null }) } as Repository);
    await app2.ready();
    const res = await app2.inject({ method: 'GET', url: `/admin/users/${DEMO_USER}/detail${WHY}` });
    expect(res.statusCode, res.body).toBe(200);
    const m = (res.json() as { mother: MotherCard }).mother;
    expect(m.orders.total).toBe(0);
    expect(m.orders.unavailable, 'nothing failed — she simply has no number').toBe(false);
    expect(m.course.unlocked).toBe(false);
    expect(m.course.unavailable).toBe(false);
  });
});

describe('a read that failed is not an answer', () => {
  /** Rebuild the server with one repository method broken, as production breaks. */
  async function withBroken(patch: Partial<Repository>): Promise<MotherCard> {
    const app2 = serve({ ...repo, ...patch } as Repository);
    await app2.ready();
    const res = await app2.inject({ method: 'GET', url: `/admin/users/${DEMO_USER}/detail${WHY}` });
    expect(res.statusCode, res.body).toBe(200);
    return (res.json() as { mother: MotherCard }).mother;
  }

  it('does not report «заказов нет» when shop_orders was unreachable', async () => {
    // She is on the phone holding a Kaspi receipt. «Заказов на этот номер нет»
    // is worse than saying nothing.
    await buyTheCombo();
    const m = await withBroken({
      shopOrdersByPhone: async () => { throw new Error('shop_orders unreachable'); },
    });
    expect(m.orders.unavailable, 'the failure has to reach the screen').toBe(true);
    expect(m.orders.total).toBe(0);
  });

  it('still returns the clinical card when the shop is down', async () => {
    // Best-effort remains best-effort: a broken shop must not 500 a record a
    // clinician is opening.
    const m = await withBroken({
      shopOrdersByPhone: async () => { throw new Error('shop_orders unreachable'); },
    });
    expect(m.stage.length).toBeGreaterThan(0);
    expect(m.course.unavailable).toBe(false);
  });

  it('does not report «комплект не покупали» when the entitlement read failed', async () => {
    const id = await buyTheCombo();
    await setStatus(id, 'shipped');
    const m = await withBroken({
      hasEntitlement: async () => { throw new Error('entitlements unreachable'); },
    });
    expect(m.course.unavailable).toBe(true);
    expect(m.course.unlocked).toBe(false);
    expect(m.course.neverStarted, 'never accuse her off a read we did not get').toBe(false);
    expect(m.orders.unavailable, 'the shop was fine').toBe(false);
  });

  it('treats a failed progress read as an unknown course too', async () => {
    const m = await withBroken({
      courseProgress: async () => { throw new Error('course_progress unreachable'); },
    });
    expect(m.course.unavailable).toBe(true);
  });

  it('says the totals are a window when the window came back full', async () => {
    // 100 rows is the route's cap. A customer past it has a spend total
    // missing her earliest purchases, and the card has to admit it.
    const many = Array.from({ length: 100 }, (_, i) => ({
      id: `o${i}`, customerName: 'Айгерим', phone: SPOKEN, phoneNormalized: '77015551122',
      city: 'Астана', address: 'пр. Абая 1', note: null,
      totalMinor: 1000, discountMinor: 0, status: 'delivered',
      createdAt: `2026-01-01T00:00:${String(i).padStart(2, '0')}.000Z`, items: [],
    }));
    const m = await withBroken({ shopOrdersByPhone: async () => many as never });
    expect(m.orders.truncated).toBe(true);
    expect(m.orders.window).toBe(100);
    expect(m.orders.total).toBe(100);
  });

  it('claims no window for a customer who fits inside it', async () => {
    await buyTheCombo();
    const m = await card();
    expect(m.orders.truncated).toBe(false);
    expect(m.orders.window).toBeNull();
  });
});

describe('the course block', () => {
  it('is locked before the parcel goes out', async () => {
    await buyTheCombo();
    const m = await card();
    expect(m.course.unlocked).toBe(false);
    expect(m.course.neverStarted, 'nothing to chase about a course she does not own').toBe(false);
  });

  it('says «доступ есть, но ни разу не открывала» once the комплект ships', async () => {
    const id = await buyTheCombo();
    await setStatus(id, 'shipped');
    const m = await card();
    // Shipping the комплект grants the course against the NORMALISED number,
    // which the card then has to find again from her profile's number.
    expect(m.course.unlocked, 'the entitlement was granted under a form the card cannot see').toBe(true);
    expect(m.course.started).toBe(0);
    expect(m.course.neverStarted).toBe(true);
    expect(m.course.lastAt).toBeNull();
  });

  it('stops flagging her the moment she opens a lesson', async () => {
    const id = await buyTheCombo();
    await setStatus(id, 'shipped');

    // A lesson to watch, published through the panel the way content is.
    const put = await app.inject({
      method: 'PUT', url: '/admin/course/lessons',
      payload: {
        titleRu: 'Сон новорождённого', titleKk: 'Нәрестенің ұйқысы',
        youtubeUrl: 'https://youtu.be/abc12345678', published: true,
      },
    });
    expect(put.statusCode, put.body).toBe(200);
    const lessonId = put.json().id as string;

    // Posted the way the app posts it: authenticated, keyed on her phone.
    const res = await app.inject({
      method: 'POST', url: '/course/progress',
      payload: { lessonId, positionSeconds: 120, durationSeconds: 600, completed: true },
    });
    expect(res.statusCode, res.body).toBe(200);

    const m = await card();
    expect(m.course.started).toBe(1);
    expect(m.course.completed).toBe(1);
    expect(m.course.neverStarted).toBe(false);
    expect(m.course.lastAt).not.toBeNull();
  });
});
