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

export interface IngestItem {
  type: 'telemetry' | 'location';
  payload: Record<string, unknown>;
}

export interface IngestDeps {
  repo: Repository;
  cacheLocation: (fix: ChildLocationFix) => Promise<void>;
  resolveTransition: (childId: string, fenceId: string, inside: boolean) => Promise<'enter' | 'exit' | null>;
  checkInside: (coords: ChildLocationFix['coords'], fence: import('@fcs/shared').Geofence) => boolean;
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
}

export interface IngestSummary {
  telemetryCount: number;
  locationCount: number;
  emergencies: number;
  geofenceEvents: GeofenceEvent[];
  rejected: number;
}

export async function handleIngestBatch(
  items: IngestItem[],
  deps: IngestDeps,
): Promise<IngestSummary> {
  const summary: IngestSummary = {
    telemetryCount: 0,
    locationCount: 0,
    emergencies: 0,
    geofenceEvents: [],
    rejected: 0,
  };

  for (const item of items) {
    try {
      if (item.type === 'telemetry') {
        await ingestTelemetry(item.payload as unknown as BandTelemetry, deps, summary);
      } else if (item.type === 'location') {
        await ingestLocation(item.payload as unknown as ChildLocationFix, deps, summary);
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
  }
  // Server-side triage backstop (the device already triaged, but never trust the client).
  const triage = assessTelemetry(t);
  await deps.repo.insertHealthMetric({ ...t, userId, triageSeverity: triage.severity });
  summary.telemetryCount++;

  if (triage.forceEmergencyScreen) {
    summary.emergencies++;
    await deps.sendEmergencyPush(userId, triage);
  }
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
  await Promise.all([deps.cacheLocation(fix), deps.repo.insertLocation(fix)]);
  summary.locationCount++;

  const fences = await deps.repo.loadGeofences(fix.childId);
  for (const fence of fences) {
    const inside = deps.checkInside(fix.coords, fence);
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
    summary.geofenceEvents.push(evt);
  }
}
