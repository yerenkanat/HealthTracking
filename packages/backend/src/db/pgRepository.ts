/**
 * Postgres-backed Repository (TimescaleDB + PostGIS). Uses `pg`.
 * Geo queries mirror the examples in db/schema.sql. Kept thin: parameterised SQL,
 * no ORM. Health/location columns should be envelope-encrypted at the app layer
 * before reaching here in production (Data Privacy Officer).
 */

import { Pool } from 'pg';
import type {
  BandTelemetry,
  BpCalibration,
  ChildLocationFix,
  Geofence,
  GeofenceEvent,
  TriageSeverity,
} from '@fcs/shared';
import type { Repository } from './repository';

export function createPgRepository(pool: Pool): Repository {
  return {
    async insertHealthMetric(m: BandTelemetry & { userId: string; triageSeverity: TriageSeverity }) {
      await pool.query(
        `INSERT INTO pregnancy_health_metrics
           (device_id, user_id, recorded_at, core_temp_c, skin_temp_c, heart_rate_bpm,
            spo2_pct, systolic_mmhg, diastolic_mmhg, during_sleep, triage_severity)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
        [
          m.deviceId, m.userId, m.recordedAt, m.coreTempC ?? null, m.skinTempC ?? null,
          m.heartRateBpm ?? null, m.spo2Pct ?? null, m.systolicMmHg ?? null,
          m.diastolicMmHg ?? null, m.duringSleep ?? false, m.triageSeverity,
        ],
      );
    },

    async insertBpCalibration(userId, cal: BpCalibration & { cuffSystolic: number; cuffDiastolic: number; ppgSystolic: number; ppgDiastolic: number }) {
      await pool.query(
        `INSERT INTO bp_calibration
           (user_id, measured_at, cuff_systolic, cuff_diastolic, ppg_systolic,
            ppg_diastolic, systolic_offset, diastolic_offset)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [userId, cal.calibratedAt, cal.cuffSystolic, cal.cuffDiastolic, cal.ppgSystolic,
         cal.ppgDiastolic, cal.systolicOffset, cal.diastolicOffset],
      );
    },

    async loadGeofences(childId): Promise<Geofence[]> {
      const { rows } = await pool.query(
        `SELECT id, name, shape, radius_m,
                ST_Y(center::geometry) AS clat, ST_X(center::geometry) AS clng,
                ST_AsGeoJSON(area) AS area_geojson
         FROM geofences WHERE child_id = $1`,
        [childId],
      );
      return rows.map((r): Geofence => {
        if (r.shape === 'circle') {
          return { id: r.id, name: r.name, shape: 'circle', center: { lat: r.clat, lng: r.clng }, radiusM: r.radius_m };
        }
        const ring = JSON.parse(r.area_geojson).coordinates[0] as [number, number][];
        return { id: r.id, name: r.name, shape: 'polygon', vertices: ring.map(([lng, lat]) => ({ lat, lng })) };
      });
    },

    async insertGeofenceEvent(evt: GeofenceEvent) {
      await pool.query(
        `INSERT INTO geofence_events (child_id, geofence_id, transition, source, occurred_at)
         VALUES ($1,$2,$3,$4,$5)`,
        [evt.childId, evt.geofenceId, evt.transition, evt.source, evt.at],
      );
    },

    async insertLocation(fix: ChildLocationFix) {
      await pool.query(
        `INSERT INTO location_history (child_id, observed_at, geog, source, accuracy_m)
         VALUES ($1,$2, ST_MakePoint($4,$3)::geography, $5, $6)`,
        [fix.childId, fix.observedAt, fix.coords.lat, fix.coords.lng, fix.source, fix.coords.accuracyM ?? null],
      );
    },

    async guardianPushTokens(childId) {
      const { rows } = await pool.query(
        `SELECT pt.token, c.name
         FROM children c
         JOIN push_tokens pt ON pt.user_id = c.guardian_id
         WHERE c.id = $1`,
        [childId],
      );
      return { tokens: rows.map((r) => r.token), childName: rows[0]?.name ?? 'Your child' };
    },

    async guardianPushTokensForUser(userId) {
      const { rows } = await pool.query(`SELECT token FROM push_tokens WHERE user_id = $1`, [userId]);
      return rows.map((r) => r.token);
    },

    async retrieveRagPassages(_query, _locale) {
      // Wire to your vector store (pgvector / external). Returns vetted KB passages.
      return [];
    },

    async emergencyContacts(userId) {
      const { rows } = await pool.query(
        `SELECT phone_e164 FROM users WHERE id = $1 AND phone_e164 IS NOT NULL`,
        [userId],
      );
      const contacts = rows[0]?.phone_e164
        ? [{ label: 'Call your doctor', tel: rows[0].phone_e164 }]
        : [];
      contacts.push({ label: 'Call ambulance', tel: '103' });
      return contacts;
    },

    async deviceOwner(deviceId) {
      const { rows } = await pool.query(`SELECT user_id FROM devices WHERE id = $1`, [deviceId]);
      return rows[0] ? { userId: rows[0].user_id } : null;
    },

    // ---- CRUD + history ----
    async listChildren(userId) {
      const { rows } = await pool.query(`SELECT id, name FROM children WHERE guardian_id = $1 ORDER BY created_at`, [userId]);
      return rows.map((r) => ({ id: r.id, name: r.name }));
    },
    async createChild(userId, name) {
      const { rows } = await pool.query(
        `INSERT INTO children (guardian_id, name) VALUES ($1,$2) RETURNING id, name`, [userId, name]);
      return { id: rows[0].id, name: rows[0].name };
    },
    async deleteChild(childId) {
      await pool.query(`DELETE FROM children WHERE id = $1`, [childId]);
    },

    async listDevices(userId) {
      const { rows } = await pool.query(
        `SELECT id, ble_mac, model FROM devices WHERE user_id = $1 ORDER BY paired_at`, [userId]);
      // Devices table currently models bands; tags can extend this schema later.
      return rows.map((r) => ({ id: r.id, name: r.model ?? r.ble_mac, kind: 'band', childId: null }));
    },
    async createDevice(userId, d) {
      await pool.query(
        `INSERT INTO devices (id, user_id, ble_mac, model) VALUES ($1,$2,$3,$4)
         ON CONFLICT (id) DO NOTHING`, [d.id, userId, d.id, d.name]);
    },
    async deleteDevice(deviceId) {
      await pool.query(`DELETE FROM devices WHERE id = $1`, [deviceId]);
    },

    async createGeofence(childId, g) {
      if (g.shape === 'circle') {
        const { rows } = await pool.query(
          `INSERT INTO geofences (guardian_id, child_id, name, shape, center, radius_m)
           VALUES ((SELECT guardian_id FROM children WHERE id=$1), $1, $2, 'circle',
                   ST_MakePoint($4,$3)::geography, $5)
           RETURNING id`,
          [childId, g.name, g.center!.lat, g.center!.lng, g.radiusM]);
        return { ...g, id: rows[0].id };
      }
      const ring = g.vertices!.map((v) => `${v.lng} ${v.lat}`).join(',');
      const first = g.vertices![0];
      const { rows } = await pool.query(
        `INSERT INTO geofences (guardian_id, child_id, name, shape, area)
         VALUES ((SELECT guardian_id FROM children WHERE id=$1), $1, $2, 'polygon',
                 ST_GeogFromText('POLYGON((${ring},${first.lng} ${first.lat}))'))
         RETURNING id`,
        [childId, g.name]);
      return { ...g, id: rows[0].id };
    },
    async deleteGeofence(geofenceId) {
      await pool.query(`DELETE FROM geofences WHERE id = $1`, [geofenceId]);
    },

    async queryMetrics(userId, { from, to, metric }) {
      const col = {
        hr: 'heart_rate_bpm', spo2: 'spo2_pct', systolic: 'systolic_mmhg',
        diastolic: 'diastolic_mmhg', temp: 'core_temp_c',
      }[metric] ?? 'heart_rate_bpm';
      const { rows } = await pool.query(
        `SELECT recorded_at AS t, ${col} AS value FROM pregnancy_health_metrics
         WHERE user_id = $1 AND recorded_at BETWEEN $2 AND $3 AND ${col} IS NOT NULL
         ORDER BY recorded_at`, [userId, from, to]);
      return rows.map((r) => ({ t: new Date(r.t).toISOString(), value: Number(r.value) }));
    },
    async listGeofenceEvents(childId, limit) {
      const { rows } = await pool.query(
        `SELECT ge.child_id, ge.geofence_id, g.name AS geofence_name, ge.transition, ge.source, ge.occurred_at
         FROM geofence_events ge JOIN geofences g ON g.id = ge.geofence_id
         WHERE ge.child_id = $1 ORDER BY ge.occurred_at DESC LIMIT $2`, [childId, limit]);
      return rows.map((r) => ({
        childId: r.child_id, geofenceId: r.geofence_id, geofenceName: r.geofence_name,
        transition: r.transition, at: new Date(r.occurred_at).toISOString(), source: r.source,
      }));
    },
  };
}
