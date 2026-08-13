/**
 * Shared domain types — imported by both `mobile` (React Native) and `backend` (Node).
 * Keep this file free of runtime dependencies so it can be consumed by any target.
 *
 * Specialists: Lead Mobile Architect + Senior Backend Engineer (single source of truth
 * for the wire contract between device, app, and server).
 */

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

export type UUID = string;
export type ISOTimestamp = string; // e.g. "2026-07-15T09:31:00.000Z"

export interface Coordinates {
  lat: number;
  lng: number;
  /** Horizontal accuracy in meters as reported by the positioning source. */
  accuracyM?: number;
}

export type PositioningSource = 'gps' | 'wifi' | 'lbs' | 'ble';

// ---------------------------------------------------------------------------
// Pregnancy health telemetry (Smart Band)
// ---------------------------------------------------------------------------

export interface BandTelemetry {
  /**
   * The band that produced this reading, or empty for one entered by hand.
   *
   * A cuff reading a mother types in has no device to attribute it to, and it
   * is the most trustworthy number in the system — an actual cuff, not a PPG
   * estimate. Attribution for those falls back to the authenticated caller;
   * see ingestTelemetry.
   */
  deviceId: string;
  recordedAt: ISOTimestamp;
  /**
   * How the reading was obtained. Absent means a band, the historical case.
   *
   * READ BY assessTelemetry: the fever rule branches on it, and absent counts
   * as a device. Only 'manual' — a thermometer reading she typed in — can raise
   * a temperature emergency. See docs/CLINICAL-REVIEW-WATCH.md.
   */
  source?: 'band' | 'manual';
  /** Estimated CORE body temperature in °C (already calibrated from skin temp). */
  coreTempC?: number;
  /** Raw skin temperature in °C as read from the sensor, kept for auditing. */
  skinTempC?: number;
  /**
   * A temperature a device reported with no stated measurement site and no
   * stated accuracy — the Starmax watch's `当前体温`. Deliberately NOT
   * `coreTempC`: with no site there is no defensible conversion, and every
   * consumer of `coreTempC` reads it as an estimated core temperature.
   *
   * Carried and graded, never triaged — the `glucoseMmol` precedent.
   * assessTelemetry ignores it.
   */
  deviceTempC?: number;
  heartRateBpm?: number;
  spo2Pct?: number;
  /** PPG-estimated blood pressure. SCREENING ONLY — must be confirmed by a cuff. */
  systolicMmHg?: number;
  diastolicMmHg?: number;
  /**
   * Blood glucose in mmol/L. A WELLNESS reading (a typed glucometer value, or the
   * band's optical estimate) — stored and shown, but NOT run through triage: an
   * estimate must never force the Emergency screen. assessTelemetry ignores it.
   */
  glucoseMmol?: number;
  /** True when the sample was captured while the wearer was detected asleep. */
  duringSleep?: boolean;
  battery?: number;
  /**
   * The band's own firmware version, e.g. "v1.2.3", when it reported one.
   *
   * Absent means the device has not told us — which the back office prints as
   * «не сообщалась», never as a dash. The server stamps it on the device row
   * so support can answer «какая прошивка на её часах» without a home visit.
   */
  firmware?: string;
}

export interface BpCalibration {
  /** Coefficients from the last manual tonometer reading, see calibration.ts. */
  systolicOffset: number;
  diastolicOffset: number;
  calibratedAt: ISOTimestamp;
}

// ---------------------------------------------------------------------------
// Child tracking (Beacon / GPS / Wi-Fi / LBS)
// ---------------------------------------------------------------------------

export interface BeaconReading {
  /** iBeacon proximity UUID (or Tuya tag id for non-iBeacon tags). */
  uuid: string;
  major?: number;
  minor?: number;
  rssi: number;
  /** Calibrated TX power @ 1m, from the beacon's advertisement or a lookup table. */
  txPower?: number;
  /** Derived straight-line distance estimate in meters. */
  distanceM?: number;
  observedAt: ISOTimestamp;
}

export interface ChildLocationFix {
  childId: UUID;
  coords: Coordinates;
  source: PositioningSource;
  observedAt: ISOTimestamp;
}

// ---------------------------------------------------------------------------
// Geofencing
// ---------------------------------------------------------------------------

export type GeofenceShape = 'circle' | 'polygon';

export interface CircleGeofence {
  id: UUID;
  name: string; // "Home", "School"
  shape: 'circle';
  center: Coordinates;
  radiusM: number;
}

export interface PolygonGeofence {
  id: UUID;
  name: string;
  shape: 'polygon';
  /** Ordered ring of vertices; first and last need not be equal (auto-closed). */
  vertices: Coordinates[];
}

export type Geofence = CircleGeofence | PolygonGeofence;

export type GeofenceTransition = 'enter' | 'exit';

export interface GeofenceEvent {
  childId: UUID;
  geofenceId: UUID;
  geofenceName: string;
  transition: GeofenceTransition;
  at: ISOTimestamp;
  source: PositioningSource;
}

// ---------------------------------------------------------------------------
// Triage (medical safety) — see triage.ts for the logic
// ---------------------------------------------------------------------------

export type TriageSeverity = 'ok' | 'info' | 'warning' | 'emergency';

export interface TriageFinding {
  code: string;           // machine key, e.g. "PREECLAMPSIA_BP"
  severity: TriageSeverity;
  metric: string;         // "systolicMmHg"
  message: string;        // human-facing, localized upstream
  value?: number;
  threshold?: number;
}

export interface TriageResult {
  severity: TriageSeverity;
  findings: TriageFinding[];
  /** When true the app must render the Emergency Rescue Screen and bypass chat. */
  forceEmergencyScreen: boolean;
}
