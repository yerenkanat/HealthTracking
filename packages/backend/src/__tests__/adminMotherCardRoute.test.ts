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

/** The number as staff type it from a phone call. */
const SPOKEN = '+7 (701) 555-11-22';
/** The same number, as her account holds it. */
const DIALLED = '+77015551122';

let repo: Repository;
let app: FastifyInstance;

beforeEach(async () => {
  repo = createMemoryRepository();
  app = buildServer(
    {
      repo,
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
  await app.ready();
  await setProfile({});
});

async function setProfile(patch: Record<string, unknown>): Promise<void> {
  await repo.upsertProfile(DEMO_USER, {
    displayName: 'Айгерим',
    phone: DIALLED,
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

  it('finds nothing, and does not fall over, for a profile with no phone', async () => {
    await setProfile({ phone: null });
    const m = await card();
    expect(m.orders.total).toBe(0);
    expect(m.course.unlocked).toBe(false);
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
