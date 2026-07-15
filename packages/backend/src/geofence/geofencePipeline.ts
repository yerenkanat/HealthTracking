/**
 * Ingest a child location fix and emit debounced geofence notifications.
 * Ties together: GeofenceTracker (hysteresis) → Redis (cross-request state +
 * duplicate suppression) → Postgres (event log) → push.ts (parent alert).
 *
 * Specialists: Geofencing Specialist + Backend Engineer + Nudge Master.
 */

import type { ChildLocationFix, Geofence, GeofenceEvent } from '@fcs/shared';
import { checkGeofenceBoundary } from './geofence';
import { resolveTransition, setChildLastLocation, redis, keys } from '../cache/redis';
import { geofenceCopy, sendPush } from '../notifications/push';

interface Deps {
  loadGeofences: (childId: string) => Promise<Geofence[]>;
  loadGuardianPushTokens: (childId: string) => Promise<{ tokens: string[]; childName: string }>;
  persistEvent: (evt: GeofenceEvent) => Promise<void>;
  persistLocation: (fix: ChildLocationFix) => Promise<void>;
}

/**
 * Handle one incoming fix. Redis `resolveTransition` is the authoritative
 * de-duplicator: it only returns a transition when the IN/OUT state actually
 * flips, so "arrived at School" fires exactly once — GPS drift while parked
 * inside the fence produces no state change and therefore no alert.
 *
 * Note: the on-device GeofenceTracker already applies hysteresis (buffer +
 * confirmations). This server stage is the backstop for multi-device/edge cases
 * and the durable event log.
 */
export async function ingestLocationFix(fix: ChildLocationFix, deps: Deps): Promise<GeofenceEvent[]> {
  await Promise.all([setChildLastLocation(fix), deps.persistLocation(fix)]);

  const fences = await deps.loadGeofences(fix.childId);
  const emitted: GeofenceEvent[] = [];

  for (const fence of fences) {
    const { inside } = checkGeofenceBoundary(fix.coords, fence);
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
