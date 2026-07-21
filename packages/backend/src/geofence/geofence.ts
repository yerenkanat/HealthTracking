/**
 * Geofence geometry + jitter-free crossing detection.
 * Specialist: Geofencing & Maps Specialist.
 *
 * Two concerns, kept separate:
 *   1. GEOMETRY — is a point inside a circle / polygon? (pure functions, testable)
 *   2. STATE   — did we cross a boundary *for real*, or is it GPS drift? (hysteresis)
 *
 * The geometry mirrors the PostGIS queries in schema.sql so the edge/mobile path
 * and the server path agree. Use this for on-device / edge evaluation; use PostGIS
 * for historical/batch queries.
 */

import type { Coordinates, Geofence, GeofenceTransition } from '@fcs/shared';

const EARTH_RADIUS_M = 6_371_000;

/** Haversine great-circle distance in meters. */
export function haversineM(a: Coordinates, b: Coordinates): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Ray-casting point-in-polygon on lat/lng. Good for city-scale fences. */
export function pointInPolygon(pt: Coordinates, ring: Coordinates[]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i].lng,
      yi = ring[i].lat;
    const xj = ring[j].lng,
      yj = ring[j].lat;
    const intersect =
      yi > pt.lat !== yj > pt.lat &&
      pt.lng < ((xj - xi) * (pt.lat - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

/** Signed distance to the boundary in meters (negative = inside). Powers hysteresis. */
export function signedDistanceToBoundaryM(pt: Coordinates, fence: Geofence): number {
  if (fence.shape === 'circle') {
    return haversineM(pt, fence.center) - fence.radiusM;
  }
  // Polygon: distance to nearest edge, signed by inside/outside.
  const inside = pointInPolygon(pt, fence.vertices);
  let minEdge = Infinity;
  const v = fence.vertices;
  for (let i = 0, j = v.length - 1; i < v.length; j = i++) {
    minEdge = Math.min(minEdge, distancePointToSegmentM(pt, v[j], v[i]));
  }
  return inside ? -minEdge : minEdge;
}

/**
 * checkGeofenceBoundary — the function named in the spec.
 * Returns whether the point is inside, plus its signed distance to the edge.
 */
export function checkGeofenceBoundary(
  childCoords: Coordinates,
  geofence: Geofence,
): { inside: boolean; signedDistanceM: number } {
  const signed = signedDistanceToBoundaryM(childCoords, geofence);
  return { inside: signed <= 0, signedDistanceM: signed };
}

// ---------------------------------------------------------------------------
// Hysteresis state machine — prevents duplicate/flapping alerts from GPS drift
// ---------------------------------------------------------------------------
export type FenceState = 'inside' | 'outside';

export interface HysteresisConfig {
  /** Must be this far PAST the boundary to flip state (meters). Kills edge jitter. */
  bufferM: number;
  /** Must sustain the new side for this many consecutive fixes before alerting. */
  confirmations: number;
  /** Ignore fixes worse than this accuracy (meters) — they can't be trusted. */
  maxAccuracyM: number;
}

const DEFAULT_HYSTERESIS: HysteresisConfig = {
  bufferM: 30,
  confirmations: 2,
  maxAccuracyM: 100,
};

/** Ignore fixes vaguer than this; see HysteresisConfig.maxAccuracyM. */
export const MAX_USABLE_ACCURACY_M = DEFAULT_HYSTERESIS.maxAccuracyM;

/**
 * The buffer to apply to one fence — the twin of zone_hysteresis.dart's
 * _bufferFor, and it must stay in step with it.
 *
 * "Inside" means a buffer deep, so a fence that is nowhere a buffer deep can
 * never be entered and its enter alert is silently impossible. A circle's
 * deepest point is its centre, at exactly the radius. A polygon has no single
 * depth, so the distance from its centroid to the nearest edge stands in: not
 * the true inradius, but never larger, so the buffer it yields is never too
 * big to enter.
 */
export function bufferForFence(fence: Geofence, cfg: HysteresisConfig = DEFAULT_HYSTERESIS): number {
  if (fence.shape === 'circle') {
    const r = fence.radiusM ?? 0;
    return cfg.bufferM < r ? cfg.bufferM : r / 2;
  }
  const v = fence.vertices;
  if (!v || v.length < 3) return cfg.bufferM;
  const centroid = {
    lat: v.reduce((s, p) => s + p.lat, 0) / v.length,
    lng: v.reduce((s, p) => s + p.lng, 0) / v.length,
  };
  const depth = -signedDistanceToBoundaryM(centroid, fence);
  if (Number.isNaN(depth) || depth <= 0) return cfg.bufferM;
  return cfg.bufferM < depth ? cfg.bufferM : depth / 2;
}

interface FenceRuntime {
  state: FenceState;
  pendingSide: FenceState | null;
  pendingCount: number;
}

/**
 * Per (child, fence) transition detector. Feed it fixes; it emits a transition
 * ONLY on a confirmed, buffered boundary crossing.
 *
 *   detector.update(coords, accuracyM)  → 'enter' | 'exit' | null
 */
export class GeofenceTracker {
  private runtime = new Map<string, FenceRuntime>();
  constructor(
    private fences: Geofence[],
    private cfg: HysteresisConfig = DEFAULT_HYSTERESIS,
  ) {}

  update(
    coords: Coordinates,
    accuracyM = 0,
  ): Array<{ fence: Geofence; transition: GeofenceTransition }> {
    const out: Array<{ fence: Geofence; transition: GeofenceTransition }> = [];
    // Reject low-quality fixes outright — do not let them move any state machine.
    if (accuracyM > this.cfg.maxAccuracyM) return out;

    for (const fence of this.fences) {
      const rt =
        this.runtime.get(fence.id) ??
        ({ state: 'outside', pendingSide: null, pendingCount: 0 } as FenceRuntime);

      const signed = signedDistanceToBoundaryM(coords, fence);
      // Buffered sides: only "definitely inside" / "definitely outside" count.
      let observed: FenceState | null = null;
      // Per-fence: a zone smaller than the buffer could never be entered.
      const buffer = bufferForFence(fence, this.cfg);
      if (signed <= -buffer) observed = 'inside';
      else if (signed >= buffer) observed = 'outside';
      // else: within the buffer band → ambiguous, hold current state.

      if (observed && observed !== rt.state) {
        if (rt.pendingSide === observed) {
          rt.pendingCount += 1;
        } else {
          rt.pendingSide = observed;
          rt.pendingCount = 1;
        }
        if (rt.pendingCount >= this.cfg.confirmations) {
          rt.state = observed;
          rt.pendingSide = null;
          rt.pendingCount = 0;
          out.push({ fence, transition: observed === 'inside' ? 'enter' : 'exit' });
        }
      } else {
        // Same side (or ambiguous): clear any pending flip.
        rt.pendingSide = null;
        rt.pendingCount = 0;
      }
      this.runtime.set(fence.id, rt);
    }
    return out;
  }

  /** Seed initial state (e.g. from persisted Redis state) to avoid a false alert on boot. */
  seed(fenceId: string, state: FenceState): void {
    this.runtime.set(fenceId, { state, pendingSide: null, pendingCount: 0 });
  }
}

// ---------------------------------------------------------------------------
function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

function distancePointToSegmentM(p: Coordinates, a: Coordinates, b: Coordinates): number {
  // Local equirectangular projection (fine at fence scale) → point-segment distance.
  const latRef = toRad((a.lat + b.lat) / 2);
  const toXY = (c: Coordinates) => ({
    x: toRad(c.lng) * Math.cos(latRef) * EARTH_RADIUS_M,
    y: toRad(c.lat) * EARTH_RADIUS_M,
  });
  const P = toXY(p),
    A = toXY(a),
    B = toXY(b);
  const dx = B.x - A.x,
    dy = B.y - A.y;
  const lenSq = dx * dx + dy * dy;
  const t = lenSq === 0 ? 0 : Math.max(0, Math.min(1, ((P.x - A.x) * dx + (P.y - A.y) * dy) / lenSq));
  const projX = A.x + t * dx,
    projY = A.y + t * dy;
  return Math.hypot(P.x - projX, P.y - projY);
}
