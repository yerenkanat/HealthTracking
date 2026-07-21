/**
 * Ingest a child location fix and emit debounced geofence notifications.
 * Ties together: GeofenceTracker (hysteresis) → Redis (cross-request state +
 * duplicate suppression) → Postgres (event log) → push.ts (parent alert).
 *
 * Specialists: Geofencing Specialist + Backend Engineer + Nudge Master.
 */

import type { ChildLocationFix, Geofence, GeofenceEvent } from '@fcs/shared';
import { signedDistanceToBoundaryM, bufferForFence, MAX_USABLE_ACCURACY_M } from './geofence';
import { resolveTransition, setChildLastLocation, redis, keys } from '../cache/redis';
import { geofenceCopy, sendPush } from '../notifications/push';

interface Deps {
  loadGeofences: (childId: string) => Promise<Geofence[]>;
  loadGuardianPushTokens: (childId: string) => Promise<{ tokens: string[]; childName: string }>;
  persistEvent: (evt: GeofenceEvent) => Promise<void>;
  persistLocation: (fix: ChildLocationFix) => Promise<void>;
}

/**
 * Handle one incoming fix. Redis `resolveTransition` de-duplicates: it only
 * returns a transition when the IN/OUT state flips, so a fix that agrees with
 * the last one produces no alert.
 *
 * That is NOT enough on its own, and the note that used to sit here said it
 * was: "the on-device GeofenceTracker already applies hysteresis". It does not
 * — that class was wired to nothing, and the app resolved zones with a bare
 * inside/outside test. So both ends had the same hole, and each one's comment
 * pointed at the other.
 *
 * GPS drift across a boundary IS a state flip: a child standing still at the
 * edge of the school fence alternates in/out, and every alternation reached
 * Redis as a genuine change and a parent's phone as an alert. Six jittery
 * fixes produced five alerts in the on-device equivalent.
 *
 * The buffer band below fixes that without any new stored state: a fix too
 * close to the boundary to call is skipped entirely, so Redis keeps whatever
 * it had. Confirmation counting stays on the device, where the per-fence
 * pending state already lives.
 */
export async function ingestLocationFix(fix: ChildLocationFix, deps: Deps): Promise<GeofenceEvent[]> {
  await Promise.all([setChildLastLocation(fix), deps.persistLocation(fix)]);

  const fences = await deps.loadGeofences(fix.childId);
  const emitted: GeofenceEvent[] = [];

  // A fix too vague to place cannot tell which side of a fence anyone is on.
  // Acting on one is how a phone reports a child leaving school from inside
  // the classroom.
  const accuracyM = fix.coords.accuracyM;
  if (accuracyM != null && accuracyM > MAX_USABLE_ACCURACY_M) return emitted;

  for (const fence of fences) {
    const signed = signedDistanceToBoundaryM(fix.coords, fence);
    if (Number.isNaN(signed)) continue; // a malformed fence decides nothing
    // Within the buffer band the answer is "cannot tell". Skipping leaves the
    // stored state alone, which is the whole point: silence, not a guess.
    if (Math.abs(signed) < bufferForFence(fence)) continue;
    const inside = signed <= 0;
    const transition = await resolveTransition(fix.childId, fence.id, inside);
    if (!transition) continue; // no state change → suppress duplicate

    const evt: GeofenceEvent = {
      childId: fix.childId,
      geofenceId: fence.id,
      geofenceName: fence.name,
      transition,
      at: fix.observedAt,
      source: fix.source,
    };
    await deps.persistEvent(evt);

    const { tokens, childName } = await deps.loadGuardianPushTokens(fix.childId);
    await sendPush(tokens, geofenceCopy(evt, childName));
    emitted.push(evt);
  }
  return emitted;
}

/** Warm the tracker's state after a restart so we don't false-alert on the first fix. */
export async function primeGeofenceState(childId: string, fences: Geofence[]): Promise<void> {
  const key = keys.geofenceState(childId);
  const existing = await redis.hgetall(key);
  // Nothing to prime if Redis already holds state; otherwise leave unset so the
  // first fix establishes a baseline without emitting (resolveTransition guards this).
  if (Object.keys(existing).length === 0) {
    void fences; // baseline established lazily on first fix
  }
}
