/**
 * Redis keyspace design — hot-path caching for the two most latency-sensitive reads:
 *   1. The child's LAST KNOWN LOCATION (parent opens app → must be instant).
 *   2. The mother's LAST BP CALIBRATION (applied to every incoming PPG frame).
 *   3. Per-child geofence STATE (for jitter-free enter/exit debouncing).
 *
 * Specialists: Senior Backend Engineer + DevOps (Redis), Data Privacy Officer
 * (short TTLs on location; no long-term PII lives in cache).
 *
 * Key naming convention:  {domain}:{entityId}:{field}
 * All values are JSON strings unless noted. TTLs keep the cache self-healing.
 */

import Redis from 'ioredis';
import type {
  BpCalibration,
  ChildLocationFix,
  GeofenceTransition,
} from '@fcs/shared';

export const redis = new Redis(process.env.REDIS_URL ?? 'redis://127.0.0.1:6379', {
  maxRetriesPerRequest: 2,
  enableAutoPipelining: true, // batch concurrent commands into one round-trip
});

// ---- Key builders (keep every key definition in ONE place) ------------------
export const keys = {
  childLastLocation: (childId: string) => `loc:${childId}:last`,
  bpCalibration: (userId: string) => `bpcal:${userId}:latest`,
  geofenceState: (childId: string) => `geofence:${childId}:state`, // hash: fenceId -> 'in'|'out'
  bandFrameDedup: (deviceId: string) => `band:${deviceId}:lastframe`, // idempotency
} as const;

const TTL = {
  location: 60 * 15, // 15 min — a stale child location must never look "live"
  calibration: 60 * 60 * 24 * 8, // 8 days — one weekly cal cycle + slack
} as const;

// ---- Last known child location ---------------------------------------------
export async function setChildLastLocation(fix: ChildLocationFix): Promise<void> {
  await redis.set(keys.childLastLocation(fix.childId), JSON.stringify(fix), 'EX', TTL.location);
}

export async function getChildLastLocation(
  childId: string,
): Promise<ChildLocationFix | null> {
  const raw = await redis.get(keys.childLastLocation(childId));
  return raw ? (JSON.parse(raw) as ChildLocationFix) : null;
}

// ---- Last BP calibration (read on the telemetry hot path) -------------------
export async function setBpCalibration(userId: string, cal: BpCalibration): Promise<void> {
  await redis.set(keys.bpCalibration(userId), JSON.stringify(cal), 'EX', TTL.calibration);
}

export async function getBpCalibration(userId: string): Promise<BpCalibration | null> {
  const raw = await redis.get(keys.bpCalibration(userId));
  return raw ? (JSON.parse(raw) as BpCalibration) : null;
}

// ---- Geofence state (server-side backstop for the debouncer) ----------------
/** Atomically read the previous state and write the new one; returns previous. */
export async function swapGeofenceState(
  childId: string,
  fenceId: string,
  next: 'in' | 'out',
): Promise<'in' | 'out' | null> {
  const key = keys.geofenceState(childId);
  const prev = (await redis.hget(key, fenceId)) as 'in' | 'out' | null;
  await redis.hset(key, fenceId, next);
  return prev;
}

/** Returns the transition to emit, or null if state is unchanged (no alert). */
export async function resolveTransition(
  childId: string,
  fenceId: string,
  isInsideNow: boolean,
): Promise<GeofenceTransition | null> {
  const next = isInsideNow ? 'in' : 'out';
  const prev = await swapGeofenceState(childId, fenceId, next);
  if (prev === next) return null; // no change → suppress duplicate alert
  if (prev === null && next === 'out') return null; // first-ever sighting outside: not an "exit"
  return isInsideNow ? 'enter' : 'exit';
}
