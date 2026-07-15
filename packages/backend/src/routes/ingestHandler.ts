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
  const owner = await deps.repo.deviceOwner(t.deviceId);
  if (!owner) {
    summary.rejected++;
    return;
  }
  // Server-side triage backstop (the device already triaged, but never trust the client).
  const triage = assessTelemetry(t);
  await deps.repo.insertHealthMetric({ ...t, userId: owner.userId, triageSeverity: triage.severity });
  summary.telemetryCount++;

  if (triage.forceEmergencyScreen) {
    summary.emergencies++;
    await deps.sendEmergencyPush(owner.userId, triage);
  }
}

async function ingestLocation(
  fix: ChildLocationFix,
  deps: IngestDeps,
  summary: IngestSummary,
): Promise<void> {
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
