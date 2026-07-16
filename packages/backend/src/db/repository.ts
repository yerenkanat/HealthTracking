/**
 * Repository interface — the single seam between business logic and Postgres.
 * Handlers depend on THIS, not on `pg`, so they are testable with fakes.
 * A thin pg-backed implementation sketch lives in pgRepository.ts.
 */

import type {
  BandTelemetry,
  BpCalibration,
  ChildLocationFix,
  Geofence,
  GeofenceEvent,
  TriageSeverity,
} from '@fcs/shared';

export interface Repository {
  // Health
  insertHealthMetric(m: BandTelemetry & { userId: string; triageSeverity: TriageSeverity }): Promise<void>;
  insertBpCalibration(userId: string, cal: BpCalibration & { cuffSystolic: number; cuffDiastolic: number; ppgSystolic: number; ppgDiastolic: number }): Promise<void>;

  // Child / geofence
  loadGeofences(childId: string): Promise<Geofence[]>;
  insertGeofenceEvent(evt: GeofenceEvent): Promise<void>;
  insertLocation(fix: ChildLocationFix): Promise<void>;

  // Push
  guardianPushTokens(childId: string): Promise<{ tokens: string[]; childName: string }>;
  guardianPushTokensForUser(userId: string): Promise<string[]>;

  // AI grounding
  retrieveRagPassages(query: string, locale: string): Promise<string[]>;

  // Emergency routing
  emergencyContacts(userId: string): Promise<Array<{ label: string; tel: string }>>;
  deviceOwner(deviceId: string): Promise<{ userId: string } | null>;

  // ---- CRUD + history (client API) ----
  listChildren(userId: string): Promise<Array<{ id: string; name: string }>>;
  createChild(userId: string, name: string): Promise<{ id: string; name: string }>;
  deleteChild(childId: string): Promise<void>;

  listDevices(userId: string): Promise<Array<{ id: string; name: string; kind: string; childId: string | null }>>;
  createDevice(userId: string, d: { id: string; name: string; kind: string; childId?: string | null }): Promise<void>;
  deleteDevice(deviceId: string): Promise<void>;

  createGeofence(childId: string, g: Geofence): Promise<Geofence>;
  deleteGeofence(geofenceId: string): Promise<void>;

  queryMetrics(userId: string, opts: { from: string; to: string; metric: string }): Promise<Array<{ t: string; value: number }>>;
  listGeofenceEvents(childId: string, limit: number): Promise<GeofenceEvent[]>;
}
