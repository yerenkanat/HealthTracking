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

  /// NOT WIRED UP. Declared for idempotent telemetry ingest and used by
  /// nothing, so band frames are not deduplicated at all.
  ///
  /// That matters because TelemetryBatcher requeues a whole batch whenever a
  /// flush fails — including when the server processed it and the RESPONSE was
  /// lost. The same readings then arrive twice: duplicate rows in the history,
  /// and a second emergency push for one reading.
  ///
  /// Left declared rather than deleted because the fix belongs in the database,
  /// not here: a unique index on (user_id, device_id, recorded_at) makes the
  /// duplicate impossible instead of merely unlikely, and a cache that expires
  /// cannot promise idempotency anyway. Tracked in docs/INTEGRATION_STATUS.md.
  bandFrameDedup: (deviceId: string) => `band:${deviceId}:lastframe`,
} as const;

const TTL = {
  location: 60 * 15, // 15 min — a stale child location must never look "live"
  calibration: 60 * 60 * 24 * 8, // 8 days — one weekly cal cycle + slack
  /// Geofence state had NO expiry, which contradicted this file's own two
  /// stated rules: "TTLs keep the cache self-healing" and "no long-term PII
  /// lives in cache". Every child ever tracked left a permanent key holding
  /// their id, including children since deleted from the account.
  ///
  /// 30 days is long enough that it never expires under any real usage — a
  /// tracked child produces fixes far more often than monthly, and each one
  /// refreshes it — while still bounding the keyspace and letting a child who
  /// stopped being tracked fall out of the cache on their own.
  ///
  /// Expiring costs at most one suppressed alert: with no stored state the
  /// next fix establishes a baseline, and resolveTransition already refuses to
  /// call a first-ever sighting an "exit".
  geofenceState: 60 * 60 * 24 * 30,
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

/**
 * Read the previous state and write the new one, as ONE operation.
 *
 * This was an HGET followed by an HSET under a comment that said "atomically".
 * It was not: two fixes for the same child arriving together — two devices, or
 * a client retry — could both read 'out', both write 'in', and both be told the
 * previous state was 'out'. Both then emit `enter`, and the parent's phone buzzes
 * twice for one arrival. The reverse interleaving loses a transition entirely,
 * which is the more serious half: a departure that never fires.
 *
 * A Lua script runs on the server as a single step, so the read and the write
 * cannot be separated by another client's.
 */
const SWAP_STATE_LUA = `
local prev = redis.call('HGET', KEYS[1], ARGV[1])
redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
redis.call('EXPIRE', KEYS[1], ARGV[3])
return prev
`;

export async function swapGeofenceState(
  childId: string,
  fenceId: string,
  next: 'in' | 'out',
): Promise<'in' | 'out' | null> {
  const prev = await redis.eval(
    SWAP_STATE_LUA,
    1,
    keys.geofenceState(childId),
    fenceId,
    next,
    String(TTL.geofenceState),
  );
  return (prev as 'in' | 'out' | null) ?? null;
}

/**
 * What to emit for a state change, or null to stay silent.
 *
 * Pure, and separated from Redis so the decision table can be tested without
 * one — the rules are small but each has a reason, and none of them were
 * covered before.
 */
export function decideTransition(
  prev: 'in' | 'out' | null,
  isInsideNow: boolean,
): GeofenceTransition | null {
  const next = isInsideNow ? 'in' : 'out';
  // Unchanged: the ordinary case, a child sitting still. Silence.
  if (prev === next) return null;
  // Nothing stored and they are outside every fence. Not a departure — we
  // never saw them arrive, and "left Home" for a child who was never home is
  // the kind of alert that teaches a parent to ignore alerts.
  if (prev === null && next === 'out') return null;
  return isInsideNow ? 'enter' : 'exit';
}

/** Returns the transition to emit, or null if state is unchanged (no alert). */
export async function resolveTransition(
  childId: string,
  fenceId: string,
  isInsideNow: boolean,
): Promise<GeofenceTransition | null> {
  const prev = await swapGeofenceState(childId, fenceId, isInsideNow ? 'in' : 'out');
  return decideTransition(prev, isInsideNow);
}
