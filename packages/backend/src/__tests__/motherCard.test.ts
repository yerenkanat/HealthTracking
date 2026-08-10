/**
 * Frame 09a — «Карточка мамы», the derived right-hand column.
 *
 * Two things here are worth more than the arithmetic:
 *
 *  - the stage is DERIVED, so every branch of it is asserted along with the
 *    sentence it gives as its reason. A stage with no working shown is a label
 *    an operator can only argue with;
 *  - a CANCELLED order is not money she spent. Counting it would make the
 *    customer who cancelled twice read as our best one — and it is the kind of
 *    number that gets quoted back to her on the phone.
 */

import { describe, it, expect } from 'vitest';
import { buildMotherCard, monthsBetween, motherStage, type MotherCardInput } from '../admin/motherCard';
import { PRODUCT_STAGES } from '../db/repository';

const NOW = '2026-08-08T10:00:00.000Z';

const base: MotherCardInput = {
  dueDate: null,
  children: [],
  orders: [],
  courseUnlocked: false,
  courseProgress: [],
  now: NOW,
};

describe('monthsBetween', () => {
  it('counts whole months only', () => {
    expect(monthsBetween('2026-05-08', '2026-08-08')).toBe(3);
    // One day short of the third month is two months, not three.
    expect(monthsBetween('2026-05-09', '2026-08-08')).toBe(2);
  });

  it('crosses a year', () => {
    expect(monthsBetween('2025-08-08', '2026-08-08')).toBe(12);
  });

  it('is zero for a date in the future rather than negative', () => {
    // A birth date that has not happened is bad data, not a child aged −3.
    expect(monthsBetween('2027-01-01', NOW)).toBe(0);
  });

  it('is zero for something that is not a date', () => {
    expect(monthsBetween('не указана', NOW)).toBe(0);
    expect(monthsBetween('2026-01-01', 'ерунда')).toBe(0);
  });

  it('does not depend on the machine timezone', () => {
    // A date-only string is UTC midnight. Read back with LOCAL getters it is
    // the previous day anywhere west of Greenwich, and February being short
    // makes that shift asymmetric: a child born on 1 January is two months old
    // on 1 March in Almaty and one month old on the identical server in New
    // York — which is the newborn/infant boundary, so the stage on her card
    // would depend on where the process happens to be running.
    const was = process.env.TZ;
    try {
      for (const tz of ['UTC', 'America/New_York', 'Asia/Almaty', 'Pacific/Kiritimati']) {
        process.env.TZ = tz;
        expect(monthsBetween('2026-01-01', '2026-03-01'), tz).toBe(2);
        expect(monthsBetween('2026-03-01', '2026-08-01'), tz).toBe(5);
      }
    } finally {
      if (was === undefined) delete process.env.TZ;
      else process.env.TZ = was;
    }
  });
});

describe('motherStage', () => {
  it('is planning when there is neither a due date nor a child', () => {
    const r = motherStage({ dueDate: null, children: [], now: NOW });
    expect(r.stage).toBe('planning');
    expect(r.reason).toContain('нет детей');
  });

  it('is pregnancy on a future due date, and says which one', () => {
    const r = motherStage({ dueDate: '2026-11-20', children: [], now: NOW });
    expect(r.stage).toBe('pregnancy');
    expect(r.reason).toContain('2026-11-20');
  });

  it('stays pregnancy for a fortnight past the due date, and says so out loud', () => {
    // Babies are late. Flipping her to «новорождённый» on the due date itself
    // would be a guess dressed as a fact.
    const r = motherStage({ dueDate: '2026-08-01', children: [], now: NOW });
    expect(r.stage).toBe('pregnancy');
    expect(r.reason).toContain('уже прошёл');
  });

  it('lets go of a due date more than a fortnight past', () => {
    const r = motherStage({ dueDate: '2026-07-01', children: [], now: NOW });
    expect(r.stage).not.toBe('pregnancy');
  });

  it('puts pregnancy ahead of an existing child', () => {
    // A mother expecting her second is being sold maternity things.
    const r = motherStage({
      dueDate: '2026-10-01',
      children: [{ name: 'Алия', dateOfBirth: '2025-08-08' }],
      now: NOW,
    });
    expect(r.stage).toBe('pregnancy');
  });

  it.each([
    ['2026-07-20', 'newborn'],
    ['2026-04-08', 'infant'],
    ['2025-06-08', 'toddler'],
    ['2019-03-08', 'any'],
  ])('reads the child born %s as %s', (dob, expected) => {
    const r = motherStage({ dueDate: null, children: [{ name: 'Алия', dateOfBirth: dob }], now: NOW });
    expect(r.stage).toBe(expected);
    expect(r.reason).toContain('Алия');
    expect(r.reason).toContain('мес.');
  });

  it('is decided by the YOUNGEST child, and names them', () => {
    // The older ones' needs are already met; whatever the youngest needs is
    // what she is short of.
    const r = motherStage({
      dueDate: null,
      children: [
        { name: 'Тимур', dateOfBirth: '2019-03-08' },
        { name: 'Алия', dateOfBirth: '2026-07-20' },
      ],
      now: NOW,
    });
    expect(r.stage).toBe('newborn');
    expect(r.reason).toContain('Алия');
    expect(r.reason).not.toContain('Тимур');
  });

  it('says it does not know when the children have no birth dates', () => {
    const r = motherStage({
      dueDate: null,
      children: [{ name: 'Тимур', dateOfBirth: null }],
      now: NOW,
    });
    expect(r.stage).toBe('any');
    expect(r.reason).toContain('не указана дата рождения');
  });

  it('ignores a child with no birth date beside one that has it', () => {
    const r = motherStage({
      dueDate: null,
      children: [
        { name: 'Тимур', dateOfBirth: null },
        { name: 'Алия', dateOfBirth: '2026-07-20' },
      ],
      now: NOW,
    });
    expect(r.stage).toBe('newborn');
  });

  it('only ever answers with a stage a product can also carry', () => {
    // The two are compared in one sentence — «этот товар для этапа
    // "новорождённый", а она на "беременность"». One vocabulary or none.
    for (const dueDate of [null, '2026-11-20', '2026-01-01']) {
      for (const dob of [null, '2026-07-20', '2026-04-08', '2025-06-08', '2010-01-01']) {
        const r = motherStage({ dueDate, children: dob ? [{ name: 'A', dateOfBirth: dob }] : [], now: NOW });
        expect(PRODUCT_STAGES as readonly string[]).toContain(r.stage);
      }
    }
  });

  it('always gives a reason', () => {
    const r = motherStage({ dueDate: null, children: [], now: NOW });
    expect(r.reason.trim().length).toBeGreaterThan(0);
  });
});

describe('buildMotherCard — her orders', () => {
  const orders = [
    { id: 'o1', status: 'delivered', totalMinor: 3900000, createdAt: '2026-05-01T09:00:00.000Z' },
    { id: 'o2', status: 'cancelled', totalMinor: 2980000, createdAt: '2026-06-01T09:00:00.000Z' },
    { id: 'o3', status: 'shipped', totalMinor: 490000, createdAt: '2026-08-01T09:00:00.000Z' },
  ];

  it('does not count a cancelled order as money she spent', () => {
    const card = buildMotherCard({ ...base, orders });
    // 39 000 + 4 900, and NOT the 29 800 she cancelled.
    expect(card.orders.spentMinor).toBe(3900000 + 490000);
  });

  it('still shows the cancelled order in the list', () => {
    // «Он был отменён третьего» is an answer. An order missing from the card
    // is an operator saying "I don't see any order".
    const card = buildMotherCard({ ...base, orders });
    expect(card.orders.total).toBe(3);
    expect(card.orders.recent.map((r) => r.id)).toContain('o2');
  });

  it('counts what is still owed to her as open', () => {
    const card = buildMotherCard({ ...base, orders });
    // shipped is open; delivered and cancelled are not.
    expect(card.orders.open).toBe(1);
  });

  it.each([
    ['new', 1],
    ['confirmed', 1],
    ['shipped', 1],
    ['delivered', 0],
    ['cancelled', 0],
  ])('treats %s as %i open', (status, open) => {
    const card = buildMotherCard({
      ...base,
      orders: [{ id: 'x', status, totalMinor: 100, createdAt: '2026-08-01T09:00:00.000Z' }],
    });
    expect(card.orders.open).toBe(open);
  });

  it('reports the NEWEST order last, whatever order they arrived in', () => {
    const card = buildMotherCard({ ...base, orders: [...orders].reverse() });
    expect(card.orders.lastAt).toBe('2026-08-01T09:00:00.000Z');
    expect(card.orders.lastStatus).toBe('shipped');
    expect(card.orders.recent[0].id).toBe('o3');
  });

  it('carries what was in the order, so «где мой заказ» is answerable here', () => {
    const card = buildMotherCard({
      ...base,
      orders: [{
        id: 'o1', status: 'shipped', totalMinor: 3900000, createdAt: '2026-08-01T09:00:00.000Z',
        items: [{ productName: 'Часы', qty: 1 }, { productName: 'Трекер', qty: 2 }],
      }],
    });
    expect(card.orders.recent[0].items).toEqual([
      { productName: 'Часы', qty: 1 },
      { productName: 'Трекер', qty: 2 },
    ]);
  });

  it('caps the list but not the counts', () => {
    // Nine orders across nine months, January to September.
    const many = Array.from({ length: 9 }, (_, i) => ({
      id: `o${i}`, status: 'delivered', totalMinor: 1000,
      createdAt: `2026-0${i + 1}-01T09:00:00.000Z`,
    }));
    const card = buildMotherCard({ ...base, orders: many });
    expect(card.orders.total).toBe(9);
    expect(card.orders.recent).toHaveLength(5);
  });

  it('says nothing rather than guessing when she has never ordered', () => {
    const card = buildMotherCard(base);
    expect(card.orders).toMatchObject({ total: 0, open: 0, spentMinor: 0, lastAt: null, lastStatus: null });
    expect(card.orders.recent).toEqual([]);
  });
});

describe('buildMotherCard — her course', () => {
  it('flags access granted and never used', () => {
    const card = buildMotherCard({ ...base, courseUnlocked: true, courseProgress: [] });
    expect(card.course.neverStarted).toBe(true);
    expect(card.course.started).toBe(0);
    expect(card.course.lastAt).toBeNull();
  });

  it('does not flag somebody who never had access', () => {
    // «Ни разу не открывала» about a course she was never sold is a support
    // agent apologising for nothing.
    const card = buildMotherCard({ ...base, courseUnlocked: false, courseProgress: [] });
    expect(card.course.neverStarted).toBe(false);
  });

  it('does not flag somebody who has opened it', () => {
    const card = buildMotherCard({
      ...base,
      courseUnlocked: true,
      courseProgress: [{ completed: false, updatedAt: '2026-08-01T09:00:00.000Z' }],
    });
    expect(card.course.neverStarted).toBe(false);
    expect(card.course.started).toBe(1);
  });

  it('counts started and completed separately', () => {
    const card = buildMotherCard({
      ...base,
      courseUnlocked: true,
      courseProgress: [
        { completed: true, updatedAt: '2026-07-01T09:00:00.000Z' },
        { completed: true, updatedAt: '2026-07-02T09:00:00.000Z' },
        { completed: false, updatedAt: '2026-08-02T09:00:00.000Z' },
      ],
    });
    expect(card.course.started).toBe(3);
    expect(card.course.completed).toBe(2);
    expect(card.course.lastAt).toBe('2026-08-02T09:00:00.000Z');
  });

  it('survives progress rows with no timestamp', () => {
    // The row shape allows it; NaN in a date is not an answer to show staff.
    const card = buildMotherCard({ ...base, courseUnlocked: true, courseProgress: [{ completed: false }] });
    expect(card.course.lastAt).toBeNull();
    expect(card.course.started).toBe(1);
  });

  it('still reports progress for somebody whose access was revoked', () => {
    const card = buildMotherCard({
      ...base,
      courseUnlocked: false,
      courseProgress: [{ completed: true, updatedAt: '2026-07-01T09:00:00.000Z' }],
    });
    expect(card.course.unlocked).toBe(false);
    expect(card.course.started).toBe(1);
    expect(card.course.neverStarted).toBe(false);
  });
});

describe('buildMotherCard — the whole block', () => {
  it('carries the stage and its working', () => {
    const card = buildMotherCard({ ...base, dueDate: '2026-11-20' });
    expect(card.stage).toBe('pregnancy');
    expect(card.stageReason).toContain('2026-11-20');
  });

  it('does not mutate the orders it was given', () => {
    const orders = [
      { id: 'a', status: 'new', totalMinor: 1, createdAt: '2026-01-01T00:00:00.000Z' },
      { id: 'b', status: 'new', totalMinor: 1, createdAt: '2026-02-01T00:00:00.000Z' },
    ];
    buildMotherCard({ ...base, orders });
    expect(orders.map((o) => o.id)).toEqual(['a', 'b']);
  });
});
