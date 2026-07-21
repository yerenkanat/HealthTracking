/**
 * QA: geofence geometry + anti-jitter hysteresis. Locks the "alert exactly once,
 * never on GPS drift" behaviour the spec calls out.
 */

import { describe, it, expect } from 'vitest';
import { checkGeofenceBoundary, haversineM, GeofenceTracker, bufferForFence } from '../geofence';
import type { CircleGeofence, Coordinates, Geofence } from '@fcs/shared';

const school: CircleGeofence = {
  id: 'school',
  name: 'School',
  shape: 'circle',
  center: { lat: 43.238949, lng: 76.889709 }, // Almaty
  radiusM: 100,
};

describe('geometry', () => {
  it('haversine ~ known distance', () => {
    const d = haversineM({ lat: 43.238949, lng: 76.889709 }, { lat: 43.239949, lng: 76.889709 });
    expect(d).toBeGreaterThan(100);
    expect(d).toBeLessThan(120);
  });
  it('point at center is inside', () => {
    expect(checkGeofenceBoundary(school.center, school).inside).toBe(true);
  });
});

describe('hysteresis — no flapping, alert once', () => {
  const tracker = new GeofenceTracker([school], {
    bufferM: 30,
    confirmations: 2,
    maxAccuracyM: 100,
  });
  const far: Coordinates = { lat: 43.245, lng: 76.9 }; // clearly outside
  const inside: Coordinates = school.center; // clearly inside

  it('needs 2 confirmations to enter, then emits exactly one enter', () => {
    expect(tracker.update(far, 10)).toEqual([]); // establish "outside"
    expect(tracker.update(inside, 10)).toEqual([]); // 1st confirmation, no emit
    const evts = tracker.update(inside, 10); // 2nd confirmation → enter
    expect(evts).toHaveLength(1);
    expect(evts[0].transition).toBe('enter');
    // Staying inside must NOT re-fire.
    expect(tracker.update(inside, 10)).toEqual([]);
  });

  it('drops low-accuracy fixes (cannot move state)', () => {
    const t2 = new GeofenceTracker([school]);
    expect(t2.update(inside, 500)).toEqual([]); // 500m accuracy → ignored
  });
});

describe('a fence too small to be entered', () => {
  // "Inside" means a buffer deep, so a fence shallower than the buffer could
  // never be entered at all — the enter alert was silently impossible, even
  // standing dead centre. The app enforces a minimum radius today, which only
  // hides this; an imported backup carries any radius at all.
  it('a 20m circle can still be entered', () => {
    const yard: Geofence = {
      id: 'yard', name: 'Yard', shape: 'circle',
      center: { lat: 43.238949, lng: 76.889709 }, radiusM: 20,
    };
    const t = new GeofenceTracker([yard]);
    const centre = { lat: 43.238949, lng: 76.889709 };
    expect(t.update(centre, 5)).toHaveLength(0); // first confirmation
    const hit = t.update(centre, 5);
    expect(hit.map((h) => h.transition)).toEqual(['enter']);
  });

  it('shrinks the buffer only for fences smaller than it', () => {
    const big: Geofence = {
      id: 'b', name: 'Big', shape: 'circle',
      center: { lat: 43.238949, lng: 76.889709 }, radiusM: 500,
    };
    const small: Geofence = { ...big, id: 's', name: 'Small', radiusM: 20 };
    expect(bufferForFence(big)).toBe(30);   // unchanged
    expect(bufferForFence(small)).toBe(10); // half the radius
  });

  it('a small polygon can be entered too', () => {
    const d = 30 / 111320;
    const plot: Geofence = {
      id: 'p', name: 'Plot', shape: 'polygon',
      vertices: [
        { lat: 43.238949 - d, lng: 76.889709 - d },
        { lat: 43.238949 - d, lng: 76.889709 + d },
        { lat: 43.238949 + d, lng: 76.889709 + d },
        { lat: 43.238949 + d, lng: 76.889709 - d },
      ],
    };
    expect(bufferForFence(plot)).toBeLessThan(30);
    const t = new GeofenceTracker([plot]);
    const centre = { lat: 43.238949, lng: 76.889709 };
    t.update(centre, 5);
    expect(t.update(centre, 5).map((h) => h.transition)).toEqual(['enter']);
  });

  it('a degenerate polygon keeps the default buffer rather than guessing', () => {
    const line: Geofence = {
      id: 'l', name: 'Line', shape: 'polygon',
      vertices: [{ lat: 43, lng: 76 }, { lat: 43.001, lng: 76 }],
    };
    expect(bufferForFence(line)).toBe(30);
  });
});
