/**
 * Frames 47/48 — «История дня».
 *
 * The trail was written on every fix and pruned at ninety days, and nothing
 * could read it. These tests are mostly about the two ways a route screen lies:
 * a line simplified until the turn is gone, and a distance that does not match
 * the line beside it.
 */

import { describe, it, expect } from 'vitest';
import {
  buildDayHistory, isSosOutcome, metresBetween, SOS_OUTCOMES, thinTrail,
  type Fix,
} from '../safety/dayHistory';

const at = (h: number, m = 0) =>
  `2026-08-08T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00.000Z`;

/** Almaty-ish. 0.001° of latitude is ~111 m. */
const fix = (h: number, m: number, lat: number, lng: number): Fix => ({
  observedAt: at(h, m),
  coords: { lat, lng },
});

describe('distance', () => {
  it('measures a known step', () => {
    // 0.001° of latitude is 111.19 m anywhere on Earth.
    const d = metresBetween({ lat: 43.238, lng: 76.889 }, { lat: 43.239, lng: 76.889 });
    expect(d).toBeGreaterThan(110);
    expect(d).toBeLessThan(112);
  });

  it('is zero for the same point', () => {
    expect(metresBetween({ lat: 43.2, lng: 76.8 }, { lat: 43.2, lng: 76.8 })).toBe(0);
  });
});

describe('thinning the trail', () => {
  it('drops jitter from standing still', () => {
    // Half an hour in a classroom: sixty fixes within a few metres.
    const fixes = Array.from({ length: 60 }, (_, i) =>
      fix(9, i, 43.238 + i * 0.000_01, 76.889));
    expect(thinTrail(fixes).length).toBeLessThan(5);
  });

  it('keeps the corner where she turned', () => {
    // The reason this is distance-based and not every-Nth. A route that loses
    // its corner is a route that says she walked through a building.
    const fixes = [
      fix(8, 0, 43.238, 76.889),
      fix(8, 1, 43.239, 76.889),
      fix(8, 2, 43.240, 76.889), // the corner
      fix(8, 3, 43.240, 76.890),
      fix(8, 4, 43.240, 76.891),
    ];
    const out = thinTrail(fixes);
    expect(out.some((p) => p.coords.lat === 43.24 && p.coords.lng === 76.889)).toBe(true);
  });

  it('always keeps the last point, however close it is to the one before', () => {
    // Where she is NOW is the one thing on this screen somebody is looking for.
    const fixes = [
      fix(8, 0, 43.238, 76.889),
      fix(8, 1, 43.250, 76.889),
      fix(8, 2, 43.250_01, 76.889),
    ];
    const out = thinTrail(fixes);
    expect(out[out.length - 1].observedAt).toBe(at(8, 2));
  });

  it('leaves one or two points alone', () => {
    expect(thinTrail([])).toEqual([]);
    const one = [fix(8, 0, 43.2, 76.8)];
    expect(thinTrail(one)).toHaveLength(1);
  });
});

describe('the day', () => {
  const crossings = [
    { at: at(8, 10), transition: 'exit' as const, zoneName: 'Дом' },
    { at: at(8, 40), transition: 'enter' as const, zoneName: 'Школа №25' },
  ];

  it('sorts fixes that arrived out of order', () => {
    // A tracker that was offline flushes its buffer at once, and the fixes do
    // not arrive in the order they happened. Drawn as they arrive, the line
    // doubles back on itself.
    const d = buildDayHistory({
      fixes: [fix(9, 0, 43.240, 76.889), fix(8, 0, 43.238, 76.889)],
      crossings: [], sos: [],
    });
    expect(d.points[0].observedAt).toBe(at(8, 0));
  });

  it('reports the length of the line it actually draws', () => {
    // Summing the raw fixes gives a bigger number than the drawn line, and
    // «3,2 км» beside a line that is plainly one kilometre reads as a bug.
    const fixes = [
      fix(8, 0, 43.238, 76.889),
      // Jitter: eight fixes going nowhere.
      ...Array.from({ length: 8 }, (_, i) => fix(8, i + 1, 43.238 + i * 0.000_02, 76.889)),
      fix(9, 0, 43.248, 76.889),
    ];
    const d = buildDayHistory({ fixes, crossings: [], sos: [] });
    let drawn = 0;
    for (let i = 1; i < d.points.length; i++) {
      drawn += metresBetween(d.points[i - 1].coords, d.points[i].coords);
    }
    expect(d.distanceM).toBe(Math.round(drawn));
  });

  it('says how many raw fixes were behind the drawn line', () => {
    // So the screen can be honest that it simplified rather than implying the
    // tracker reported four times all day.
    const fixes = Array.from({ length: 30 }, (_, i) => fix(9, i, 43.238 + i * 0.000_01, 76.889));
    const d = buildDayHistory({ fixes, crossings: [], sos: [] });
    expect(d.rawCount).toBe(30);
    expect(d.pointCount).toBeLessThan(30);
    expect(d.pointCount).toBe(d.points.length);
  });

  it('interleaves crossings and an SOS in time order', () => {
    const d = buildDayHistory({
      fixes: [],
      crossings,
      sos: [{ at: at(8, 20), lat: 43.239, lng: 76.889 }],
    });
    expect(d.events.map((e) => e.kind)).toEqual(['exit', 'sos', 'enter']);
    expect(d.events[0].zoneName).toBe('Дом');
    expect(d.events[2].zoneName).toBe('Школа №25');
  });

  it('carries the SOS position, because that is the map on frame 48', () => {
    const d = buildDayHistory({
      fixes: [], crossings: [], sos: [{ at: at(16, 41), lat: 43.239, lng: 76.887 }],
    });
    expect(d.events[0].lat).toBe(43.239);
    expect(d.events[0].lng).toBe(76.887);
  });

  it('survives a zone that has since been deleted', () => {
    // The event outlives the geofence. Dropping it would erase a crossing that
    // really happened because somebody tidied their zones afterwards.
    const d = buildDayHistory({
      fixes: [], sos: [],
      crossings: [{ at: at(8, 10), transition: 'exit', zoneName: null }],
    });
    expect(d.events).toHaveLength(1);
    expect(d.events[0].zoneName).toBeNull();
  });

  it('is an empty day, not an error, when nothing was recorded', () => {
    const d = buildDayHistory({ fixes: [], crossings: [], sos: [] });
    expect(d.points).toEqual([]);
    expect(d.distanceM).toBe(0);
    expect(d.events).toEqual([]);
  });
});

describe('«Чем закончилось»', () => {
  it('offers four outcomes in both languages', () => {
    expect(SOS_OUTCOMES).toHaveLength(4);
    for (const o of SOS_OUTCOMES) {
      expect(o.ru.length).toBeGreaterThan(3);
      expect(o.kk.length).toBeGreaterThan(3);
    }
  });

  it('refuses anything else', () => {
    expect(isSosOutcome('false_press')).toBe(true);
    expect(isSosOutcome('whatever')).toBe(false);
    expect(isSosOutcome(null)).toBe(false);
  });
});
