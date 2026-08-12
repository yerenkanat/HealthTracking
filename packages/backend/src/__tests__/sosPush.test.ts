/**
 * Screen 21's sender — the SOS that leaves the phone it was pressed on.
 *
 * Two halves of one defect. `POST /alerts` has existed and been tested since
 * the alert kinds were widened to five, and the app had no caller for it, so an
 * SOS lived and died on one handset: the back-office safety feed never saw it,
 * and neither did anybody else in the family. And there was no SOS push copy at
 * all — geofence crossings, medical emergencies, support replies and рассылки
 * each had one; the alarm this product is sold on did not.
 *
 * What is asserted here is the JOIN and the payload contract the Dart side
 * parses (app/lib/domain/notification_route.dart). Nothing between the two
 * checks the field names for us.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEMO_CHILD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { sosCopy } from '../notifications/push';

const AT = '2026-08-13T16:41:00.000Z';

type SosCall = { userId: string; alert: { childId: string; zoneName: string; at: string } };

let app: FastifyInstance;
let repo: Repository;
let sos: SosCall[];

function makeApp(notifySos?: (u: string, a: SosCall['alert']) => Promise<void>) {
  repo = createMemoryRepository();
  return buildServer(
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
      authAdmin: async () => null,
      notifySos,
    },
    { logger: false },
  );
}

beforeEach(() => {
  sos = [];
  app = makeApp(async (userId, alert) => { sos.push({ userId, alert }); });
});

describe('POST /alerts', () => {
  it('an SOS notifies the family', async () => {
    const res = await app.inject({
      method: 'POST', url: '/alerts',
      payload: { childId: DEMO_CHILD, kind: 'sos', zoneName: 'Мектеп №25', at: AT },
    });
    expect(res.statusCode).toBe(201);
    expect(sos).toHaveLength(1);
    expect(sos[0]).toEqual({
      userId: DEMO_USER,
      alert: { childId: DEMO_CHILD, zoneName: 'Мектеп №25', at: AT },
    });
    // …and it is on the feed, which is what screen 39 and the back office read.
    const stored = await repo.listAlerts(DEMO_USER, 10);
    expect(stored.some((a) => a.kind === 'sos')).toBe(true);
    await app.close();
  });

  it('a zone crossing does not — only the alarm wakes a household', async () => {
    await app.inject({
      method: 'POST', url: '/alerts',
      payload: { childId: DEMO_CHILD, kind: 'entered', zoneName: 'Үй', at: AT },
    });
    await app.inject({
      method: 'POST', url: '/alerts',
      payload: { childId: DEMO_CHILD, kind: 'checkIn', zoneName: '', at: AT },
    });
    expect(sos).toHaveLength(0);
    await app.close();
  });

  it('a push that fails does not lose the alarm', async () => {
    // The write is what must survive. A 500 here would make the app retry and
    // record the same SOS twice — and it would still not have been pushed.
    app = makeApp(async () => { throw new Error('FCM unreachable'); });
    const res = await app.inject({
      method: 'POST', url: '/alerts',
      payload: { childId: DEMO_CHILD, kind: 'sos', zoneName: '', at: AT },
    });
    expect(res.statusCode).toBe(201);
    expect((await repo.listAlerts(DEMO_USER, 10)).some((a) => a.kind === 'sos')).toBe(true);
    await app.close();
  });

  it('a box with no push channel still records the alarm', async () => {
    app = makeApp(undefined);
    const res = await app.inject({
      method: 'POST', url: '/alerts',
      payload: { childId: DEMO_CHILD, kind: 'sos', zoneName: '', at: AT },
    });
    expect(res.statusCode).toBe(201);
    await app.close();
  });
});

describe('the SOS push payload', () => {
  it('carries what screen 21 needs, under the names the app parses', () => {
    const msg = sosCopy({
      childId: 'child-1',
      childName: 'Алия',
      at: AT,
      zoneName: 'Мектеп №25',
      coords: { lat: 43.25, lng: 76.95 },
    });
    expect(msg.data).toEqual({
      screen: 'SosAlert',
      childId: 'child-1',
      childName: 'Алия',
      at: AT,
      zoneName: 'Мектеп №25',
      lat: '43.25',
      lng: '76.95',
    });
    expect(msg.title).toBe('SOS · Алия нажала кнопку');
    // The one notification allowed to break Do Not Disturb.
    expect(msg.critical).toBe(true);
    expect(msg.category).toBe('medical_emergency');
  });

  it('never invents a name for a child the row cannot identify', () => {
    const msg = sosCopy({ childId: 'child-1', childName: '', at: AT });
    expect(msg.title).toBe('SOS · нажата кнопка тревоги');
    expect(msg.data?.childName).toBeUndefined();
    // No zone and no fix: absent, not empty strings that read as data.
    expect(msg.data?.zoneName).toBeUndefined();
    expect(msg.data?.lat).toBeUndefined();
  });

  it('speaks the language on her profile', () => {
    expect(sosCopy({ childId: 'c', childName: 'Алия', at: AT }, 'kk').title)
      .toBe('SOS · Алия түймені басты');
    expect(sosCopy({ childId: 'c', childName: 'Aliya', at: AT }, 'en').title)
      .toBe('SOS · Aliya pressed the button');
  });

  it('does NOT carry the family contact — it is already on the phone', () => {
    // The medical-ID card travels over GET /children/:id/emergency and is
    // restored on every device. Putting a relative's number in a push payload
    // would write it into the OS notification store and FCM's logs to display
    // something the device can already read locally.
    const msg = sosCopy({ childId: 'c', childName: 'Алия', at: AT });
    expect(Object.keys(msg.data ?? {})).not.toContain('contactPhone');
    expect(Object.keys(msg.data ?? {})).not.toContain('contactName');
  });
});
