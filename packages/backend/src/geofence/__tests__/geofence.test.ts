/**
 * QA: geofence geometry + anti-jitter hysteresis. Locks the "alert exactly once,
 * never on GPS drift" behaviour the spec calls out.
 */

import { describe, it, expect } from 'vitest';
import { checkGeofenceBoundary, haversineM, GeofenceTracker } from '../geofence';
import type { CircleGeofence, Coordinates } from '@fcs/shared';

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
