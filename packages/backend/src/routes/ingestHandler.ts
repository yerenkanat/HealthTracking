/**
 * Pure ingest handler — the core of POST /ingest/batch.
 * The Dart TelemetryBatcher posts batched {telemetry|location} items here.
 * Depends only on injected collaborators (repo, cache, push, triage) so it is
 * unit-testable with fakes — no Fastify, DB, or network required.
 *
 * Specialists: Backend Engineer + OB-GYN (server-side emergency backstop) +
 * Geofencing Specialist.
 */

import { assessTelemetry } from '@fcs/shared';
import type { BandTelemetry, ChildLocationFix, GeofenceEvent } from '@fcs/shared';
import type { Repository } from '../db/repository';
import {
  bufferForFence,
  signedDistanceToBoundaryM,
  MAX_USABLE_ACCURACY_M,
} from '../geofence/geofence';

export interface IngestItem {
  type: 'telemetry' | 'location' | 'wearable';
  payload: Record<string, unknown>;
}

export interface IngestDeps {
  repo: Repository;
  cacheLocation: (fix: ChildLocationFix) => Promise<void>;
  resolveTransition: (childId: string, fenceId: string, inside: boolean) => Promise<'enter' | 'exit' | null>;
  // checkInside was here — a bare `signedDistance <= 0`, injected but never
  // injectable (buildServer Omitted it, so production always got that one). It
  // is now the pure geofence math imported above, applied WITH the two guards
  // that had never run. Nothing needs to fake trigonometry.
  sendEmergencyPush: (userId: string, triage: ReturnType<typeof assessTelemetry>) => Promise<void>;
  sendGeofencePush: (evt: GeofenceEvent) => Promise<void>;

  /// The authenticated caller. Every item is attributed to whoever owns the
  /// device or child it names, so without this a caller could submit data for
  /// somebody else's family — fabricating a child's location or injecting
  /// vitals that raise a false emergency. Items the caller doesn't own are
  /// counted as rejected rather than stored.
  ///
  /// Optional so existing internal callers keep working; when it is absent no
  /// ownership filtering happens, so the HTTP route always passes it.
  callerUserId?: string;

  /// When this batch reached us. Injected so a test can assert the exact
  /// timestamp stamped on the device rather than racing a clock; defaults to
  /// now, which is what production wants.
  now?: () => Date;
}

export interface IngestSummary {
  telemetryCount: number;
  locationCount: number;
  /** Watch activity/wellbeing snapshots stored (steps, calories, stress, …). */
  wearableCount: number;
  emergencies: number;
  geofenceEvents: GeofenceEvent[];
  rejected: number;
  /** Readings that were already stored (a resend of a batch whose response was
   *  lost). Counted, not stored again, and NOT re-pushed as an emergency. */
  duplicates: number;
}

export async function handleIngestBatch(
  items: IngestItem[],
  deps: IngestDeps,
): Promise<IngestSummary> {
  const summary: IngestSummary = {
    telemetryCount: 0,
    locationCount: 0,
    wearableCount: 0,
    emergencies: 0,
    geofenceEvents: [],
    rejected: 0,
    duplicates: 0,
  };

  for (const item of items) {
    try {
      if (item.type === 'telemetry') {
        await ingestTelemetry(item.payload as unknown as BandTelemetry, deps, summary);
      } else if (item.type === 'location') {
        await ingestLocation(item.payload as unknown as ChildLocationFix, deps, summary);
      } else if (item.type === 'wearable') {
        await ingestWearable(item.payload as unknown as WearableSnapshot, deps, summary);
      } else {
        summary.rejected++;
      }
    } catch {
      // One bad item must not sink the whole batch (the client will resend).
      summary.rejected++;
    }
  }
  return summary;
}

/**
 * «Это устройство только что говорило с нами.»
 *
 * The one thing that makes frame 11 mean anything: `devices.last_seen` and
 * `devices.battery_pct` were SELECTed by the fleet view and written by
 * NOTHING — there was no `UPDATE devices SET last_seen` anywhere in the
 * repository — so «последний сигнал» was empty for every device that has ever
 * existed and the battery column never moved.
 *
 * Stamped with the moment the batch REACHED us rather than the reading's own
 * recordedAt: a phone draining a three-day offline queue is talking to us now,
 * and the panel states that rule under the table.
 *
 * Its failure is swallowed on purpose, like the location cache above. This is
 * metadata about a device; the reading is already stored, and letting a failed
 * UPDATE bubble to the batch-level catch would mark the item `rejected` and
 * make the client resend a reading we already have, for ever.
 */
async function markAlive(
  deviceId: string,
  deps: IngestDeps,
  seen: { batteryPct?: number | null; firmware?: string | null },
): Promise<void> {
  try {
    await deps.repo.touchDevice(deviceId, {
      at: (deps.now?.() ?? new Date()).toISOString(),
      // Absent, not zero. A payload with no battery must leave the last known
      // one alone — 0 % would read as a flat watch.
      batteryPct: seen.batteryPct ?? null,
      firmware: seen.firmware ?? null,
    });
  } catch {
    // Nothing to do: freshness is not the data.
  }
}

async function ingestTelemetry(
  t: BandTelemetry,
  deps: IngestDeps,
  summary: IngestSummary,
): Promise<void> {
  // A reading entered by hand has no device to attribute it to.
  //
  // These were rejected outright, because attribution went only through
  // deviceOwner(). That silently dropped the most trustworthy readings the
  // product has — an actual cuff, typed in by the mother, rather than a PPG
  // estimate — so her clinician's view never showed them. They are attributed
  // to the authenticated caller instead, which is exactly as trustworthy as
  // the session that submitted them.
  const manual = t.source === 'manual' || !t.deviceId;
  let userId: string;
  if (manual) {
    if (!deps.callerUserId) {
      // No device AND no session: nothing can say whose reading this is.
      summary.rejected++;
      return;
    }
    userId = deps.callerUserId;
  } else {
    const owner = await deps.repo.deviceOwner(t.deviceId);
    if (!owner) {
      summary.rejected++;
      return;
    }
    // Readings for someone else's band are not this caller's to submit.
    if (deps.callerUserId && owner.userId !== deps.callerUserId) {
      summary.rejected++;
      return;
    }
    userId = owner.userId;
    // Before the duplicate check on purpose: a resent batch is still proof
    // that this device and this phone are talking to us right now, which is
    // the only question «на связи» asks. A manual reading marks nothing —
    // there is no device behind it to be alive.
    await markAlive(t.deviceId, deps, { batteryPct: t.battery, firmware: t.firmware });
  }
  // Server-side triage backstop (the device already triaged, but never trust the client).
  const triage = assessTelemetry(t);
  const duplicate = await deps.repo.insertHealthMetric({ ...t, userId, triageSeverity: triage.severity });
  // A resend of a reading already stored: the batcher requeues a whole batch
  // when a flush's response is lost, so this same emergency would otherwise push
  // a second time. Count it, store nothing, push nothing.
  if (duplicate) {
    summary.duplicates++;
    return;
  }
  summary.telemetryCount++;

  if (triage.forceEmergencyScreen) {
    summary.emergencies++;
    await deps.sendEmergencyPush(userId, triage);
  }
}

/**
 * The watch's activity / wellbeing snapshot for one day.
 *
 * Everything the wrist device measures that is NOT one of the four triage
 * vitals: what she did (steps, distance, calories), how her body is between
 * measurements (stress, breathing rate, MET), and the state of the device
 * itself (battery, charging, on-wrist). None of it can raise an emergency, so
 * none of it goes near triage — it is stored, and read by the clinician and
 * operator views.
 *
 * Upserted on (user, device, day) rather than appended: steps and calories are
 * the watch's own running daily totals, so thirty polls an hour would otherwise
 * write thirty rows that each say the same thing a little later.
 */
export interface WearableSnapshot {
  deviceId: string;
  day: string; // yyyy-MM-dd, the WEARER's local day
  recordedAt: string; // ISO instant of the snapshot this row was built from
  steps: number;
  kcal: number;
  meters: number;
  sleepMinutes: number;
  deepSleepMinutes: number;
  lightSleepMinutes: number;
  stress?: number;
  breathRate?: number;
  met?: number;
  batteryPercent?: number;
  charging: boolean;
  worn: boolean;
  /** The watch's firmware, when it reported one. Stamped on the device row. */
  firmware?: string;

  /**
   * The vitals a BACKFILLED day carries — averages over the day's measured
   * samples, plus the extremes. Absent on a live snapshot, which has no day to
   * average over yet; present when the app has read the watch's stored history.
   */
  heartRateAvg?: number;
  heartRateMin?: number;
  heartRateMax?: number;
  spo2Avg?: number;
  spo2Min?: number;
  systolicAvg?: number;
  diastolicAvg?: number;
  tempAvgTenths?: number;
  bloodSugarTenths?: number;
}

/**
 * A vital, or undefined if it is not one.
 *
 * The wearable row is written straight into columns with CHECK constraints, so
 * a value outside human physiology does not become a bad chart — it becomes a
 * failed INSERT, which the batch-level catch counts as `rejected`, which makes
 * the client resend the same day for ever. A decoding bug at the BLE edge would
 * therefore turn into a permanent retry loop draining her battery.
 *
 * Dropped here instead: the day is still stored, with that one metric absent,
 * which is the truth — we do not know what it was.
 */
function plausible(v: number | undefined, lo: number, hi: number): number | undefined {
  if (typeof v !== 'number' || !Number.isFinite(v)) return undefined;
  const n = Math.round(v);
  return n >= lo && n <= hi ? n : undefined;
}

async function ingestWearable(
  w: WearableSnapshot,
  deps: IngestDeps,
  summary: IngestSummary,
): Promise<void> {
  // Attributed exactly like a reading: the device that produced it decides
  // whose row this is, and a device this caller does not own is not theirs to
  // write. A snapshot with no device cannot be attributed at all — unlike a
  // hand-typed vital, nobody types in their own step count.
  const owner = await deps.repo.deviceOwner(w.deviceId);
  if (!owner) {
    summary.rejected++;
    return;
  }
  if (deps.callerUserId && owner.userId !== deps.callerUserId) {
    summary.rejected++;
    return;
  }
  await deps.repo.upsertWearableDay({
    ...w,
    userId: owner.userId,
    // Ranges match the table's CHECK constraints exactly. An implausible value
    // is dropped rather than rejected, so one mis-decoded metric costs that
    // metric and not the whole day — and never an endless resend.
    stress: plausible(w.stress, 0, 100) ?? null,
    breathRate: plausible(w.breathRate, 1, 80) ?? null,
    batteryPercent: plausible(w.batteryPercent, 0, 100) ?? null,
    heartRateAvg: plausible(w.heartRateAvg, 20, 250) ?? null,
    heartRateMin: plausible(w.heartRateMin, 20, 250) ?? null,
    heartRateMax: plausible(w.heartRateMax, 20, 250) ?? null,
    spo2Avg: plausible(w.spo2Avg, 50, 100) ?? null,
    spo2Min: plausible(w.spo2Min, 50, 100) ?? null,
    systolicAvg: plausible(w.systolicAvg, 50, 260) ?? null,
    diastolicAvg: plausible(w.diastolicAvg, 30, 200) ?? null,
    tempAvgTenths: plausible(w.tempAvgTenths, 300, 450) ?? null,
    bloodSugarTenths: plausible(w.bloodSugarTenths, 10, 300) ?? null,
  });
  // The snapshot is where the watch's own battery actually comes from today:
  // the app sends `batteryPercent` here and nothing on the telemetry item.
  await markAlive(w.deviceId, deps, { batteryPct: w.batteryPercent, firmware: w.firmware });
  summary.wearableCount++;
}

async function ingestLocation(
  fix: ChildLocationFix,
  deps: IngestDeps,
  summary: IngestSummary,
): Promise<void> {
  // A position for someone else's child must never be recorded: it would move
  // that child on their parent's map and fire geofence alerts from it.
  if (deps.callerUserId) {
    const owner = await deps.repo.childOwner(fix.childId);
    if (!owner || owner.userId !== deps.callerUserId) {
      summary.rejected++;
      return;
    }
  }
  // The durable write is what must succeed. Caching the fix is an optimisation
  // for the parent's next map open, and its failure used to sink the whole item
  // via the batch-level catch: the fix came back `rejected`, so the tracker
  // resent it on every flush — and location_history has no uniqueness
  // constraint to absorb that, unlike telemetry — while the geofence loop below
  // never ran at all.
  await deps.repo.insertLocation(fix);
  try {
    await deps.cacheLocation(fix);
  } catch {
    // Nothing to do: the fix is stored, and GET /children/:id/location falls
    // back to the table.
  }
  summary.locationCount++;

  // A fix too vague to place cannot tell which side of a fence anyone is on.
  // Acting on one is how a phone reports a child leaving school from inside the
  // classroom: indoors the platform falls back to cell towers and returns a
  // position accurate to hundreds of metres, which lands well outside a 100 m
  // school fence. Skipping leaves the stored state alone — silence, not a guess.
  const accuracyM = fix.coords.accuracyM;
  if (accuracyM != null && accuracyM > MAX_USABLE_ACCURACY_M) return;

  const fences = await deps.repo.loadGeofences(fix.childId);
  // The guardian who owns this child, resolved at most once and only if a
  // transition actually fires — needed to attribute the safety alert. In the
  // authenticated path the caller is already verified as the owner above, so no
  // extra lookup is done.
  let ownerUserId: string | null = deps.callerUserId ?? null;
  for (const fence of fences) {
    const signed = signedDistanceToBoundaryM(fix.coords, fence);
    if (Number.isNaN(signed)) continue; // a malformed fence decides nothing

    // The hysteresis band. resolveTransition only fires on a state FLIP, and
    // that is not enough on its own: GPS drift across a boundary IS a flip, so
    // a child standing still at the edge of the school fence alternates
    // in/out and every alternation reached a parent's phone as an alert.
    //
    // Within a buffer of the boundary the answer is "cannot tell", so the fix
    // is skipped and Redis keeps whatever state it had. This needs no new
    // stored state, which is why it can live here.
    if (Math.abs(signed) < bufferForFence(fence)) continue;

    const inside = signed <= 0;
    const transition = await deps.resolveTransition(fix.childId, fence.id, inside);
    if (!transition) continue; // debounced: no state change → no alert

    const evt: GeofenceEvent = {
      childId: fix.childId,
      geofenceId: fence.id,
      geofenceName: fence.name,
      transition,
      at: fix.observedAt,
      source: fix.source,
    };
    await deps.repo.insertGeofenceEvent(evt);
    await deps.sendGeofencePush(evt);

    // Also record it as a safety alert. The admin's cross-family safety feed
    // (GET /admin/safety) reads the safety_alerts table, and NOTHING wrote it:
    // the app never POSTs /alerts and this ingest path only stored crossings in
    // geofence_events. So every detection landed somewhere the operational feed
    // never looks, and the back-office safety view was permanently empty — for
    // a child-safety product, the one screen that must not be.
    ownerUserId ??= (await deps.repo.childOwner(fix.childId))?.userId ?? null;
    if (ownerUserId) {
      await deps.repo.recordAlert(ownerUserId, {
        childId: fix.childId,
        kind: transition === 'enter' ? 'entered' : 'left',
        zoneName: fence.name,
        at: fix.observedAt,
      });
    }
    summary.geofenceEvents.push(evt);
  }
}
