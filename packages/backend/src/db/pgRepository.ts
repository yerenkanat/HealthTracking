/**
 * Postgres-backed Repository (TimescaleDB + PostGIS). Uses `pg`.
 * Geo queries mirror the examples in db/schema.sql. Kept thin: parameterised SQL,
 * no ORM. Health/location columns should be envelope-encrypted at the app layer
 * before reaching here in production (Data Privacy Officer).
 */

import { Pool } from 'pg';
import { computeChildrenStats } from '../analytics/childStats.js';
import type { ContentItemRow } from './repository';
import type {
  BandTelemetry,
  BpCalibration,
  ChildLocationFix,
  Geofence,
  GeofenceEvent,
  TriageSeverity,
} from '@fcs/shared';
import type { Repository } from './repository';
import { computeBiMetrics, type BiEventKind } from '../analytics/biMetrics.js';

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
        `SELECT pt.token, c.name, u.locale
         FROM children c
         JOIN push_tokens pt ON pt.user_id = c.guardian_id
         JOIN users u        ON u.id = c.guardian_id
         WHERE c.id = $1`,
        [childId],
      );
      return {
        tokens: rows.map((r) => r.token),
        childName: rows[0]?.name ?? 'Your child',
        locale: rows[0]?.locale ?? null,
      };
    },

    async guardianPushTokensForUser(userId) {
      const { rows } = await pool.query(
        `SELECT pt.token, u.locale
           FROM push_tokens pt
           JOIN users u ON u.id = pt.user_id
          WHERE pt.user_id = $1`,
        [userId],
      );
      return { tokens: rows.map((r) => r.token), locale: rows[0]?.locale ?? null };
    },

    async deletePushToken(token) {
      await pool.query('DELETE FROM push_tokens WHERE token = $1', [token]);
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

    async childOwner(childId) {
      const { rows } = await pool.query(`SELECT guardian_id FROM children WHERE id = $1`, [childId]);
      return rows[0] ? { userId: rows[0].guardian_id } : null;
    },

    async geofenceOwner(geofenceId) {
      const { rows } = await pool.query(`SELECT guardian_id FROM geofences WHERE id = $1`, [geofenceId]);
      return rows[0] ? { userId: rows[0].guardian_id } : null;
    },

    // ---- CRUD + history ----
    async listChildren(userId) {
      const { rows } = await pool.query(`SELECT id, name FROM children WHERE guardian_id = $1 ORDER BY created_at`, [userId]);
      return rows.map((r) => ({ id: r.id, name: r.name }));
    },
    async upsertChild(userId, c) {
      // Client-supplied id (a UUID, which the ingest schema also requires) so an
      // offline-created child keeps its identity and its geofences can point at
      // it. Idempotent on the id.
      await pool.query(
        `INSERT INTO children (id, guardian_id, name, gender, date_of_birth)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (id) DO UPDATE
           SET name = EXCLUDED.name, gender = EXCLUDED.gender, date_of_birth = EXCLUDED.date_of_birth`,
        [c.id, userId, c.name, c.gender ?? null, c.dateOfBirth ?? null]);
    },
    async deleteChild(childId) {
      await pool.query(`DELETE FROM children WHERE id = $1`, [childId]);
    },

    async listDevices(userId) {
      const { rows } = await pool.query(
        `SELECT id, ble_mac, model, name, kind, child_id FROM devices WHERE user_id = $1 ORDER BY paired_at`, [userId]);
      return rows.map((r) => ({
        id: r.id, name: r.name ?? r.model ?? r.ble_mac, kind: r.kind ?? 'band', childId: r.child_id ?? null,
      }));
    },
    async createDevice(userId, d) {
      await pool.query(
        `INSERT INTO devices (id, user_id, ble_mac, model, kind, name, child_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (id) DO NOTHING`,
        [d.id, userId, d.id, d.name, d.kind, d.name, d.childId ?? null]);
    },
    async deleteDevice(deviceId) {
      await pool.query(`DELETE FROM devices WHERE id = $1`, [deviceId]);
    },

    async listAppointments(userId) {
      const { rows } = await pool.query(
        `SELECT id, title, at, note FROM appointments WHERE user_id = $1 ORDER BY at`, [userId]);
      return rows.map((r) => ({
        id: r.id, title: r.title, at: new Date(r.at).toISOString(), note: r.note ?? '',
      }));
    },
    async upsertAppointment(userId, a) {
      await pool.query(
        `INSERT INTO appointments (id, user_id, title, at, note)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title, at = EXCLUDED.at, note = EXCLUDED.note`,
        [a.id, userId, a.title, a.at, a.note ?? '']);
    },
    async appointmentOwner(id) {
      const { rows } = await pool.query(`SELECT user_id FROM appointments WHERE id = $1`, [id]);
      return rows[0] ? { userId: rows[0].user_id } : null;
    },
    async deleteAppointment(id) {
      await pool.query(`DELETE FROM appointments WHERE id = $1`, [id]);
    },

    async listMedications(userId) {
      const { rows } = await pool.query(
        `SELECT id, name, dose, per_day FROM medications WHERE user_id = $1 ORDER BY name`, [userId]);
      return rows.map((r) => ({ id: r.id, name: r.name, dose: r.dose ?? '', perDay: r.per_day }));
    },
    async upsertMedication(userId, m) {
      await pool.query(
        `INSERT INTO medications (id, user_id, name, dose, per_day)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, dose = EXCLUDED.dose, per_day = EXCLUDED.per_day`,
        [m.id, userId, m.name, m.dose, m.perDay]);
    },
    async medicationOwner(id) {
      const { rows } = await pool.query(`SELECT user_id FROM medications WHERE id = $1`, [id]);
      return rows[0] ? { userId: rows[0].user_id } : null;
    },
    async deleteMedication(id) {
      await pool.query(`DELETE FROM medications WHERE id = $1`, [id]);
    },

    async upsertGeofence(childId, g) {
      // Client-supplied id; idempotent on it.
      if (g.shape === 'circle') {
        await pool.query(
          `INSERT INTO geofences (id, guardian_id, child_id, name, shape, center, radius_m)
           VALUES ($6, (SELECT guardian_id FROM children WHERE id=$1), $1, $2, 'circle',
                   ST_MakePoint($4,$3)::geography, $5)
           ON CONFLICT (id) DO UPDATE
             SET name = EXCLUDED.name, shape = EXCLUDED.shape,
                 center = EXCLUDED.center, radius_m = EXCLUDED.radius_m, area = NULL`,
          [childId, g.name, g.center!.lat, g.center!.lng, g.radiusM, g.id]);
        return;
      }
      const ring = g.vertices!.map((v) => `${v.lng} ${v.lat}`).join(',');
      const first = g.vertices![0];
      await pool.query(
        `INSERT INTO geofences (id, guardian_id, child_id, name, shape, area)
         VALUES ($3, (SELECT guardian_id FROM children WHERE id=$1), $1, $2, 'polygon',
                 ST_GeogFromText('POLYGON((${ring},${first.lng} ${first.lat}))'))
         ON CONFLICT (id) DO UPDATE
           SET name = EXCLUDED.name, shape = EXCLUDED.shape, area = EXCLUDED.area,
               center = NULL, radius_m = NULL`,
        [childId, g.name, g.id]);
    },
    async deleteGeofence(geofenceId) {
      await pool.query(`DELETE FROM geofences WHERE id = $1`, [geofenceId]);
    },

    async recordNewbornEvent(childId, e) {
      await pool.query(
        `INSERT INTO newborn_events (child_id, at, kind, detail, duration_min)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (child_id, at, kind) DO UPDATE
           SET detail = EXCLUDED.detail, duration_min = EXCLUDED.duration_min`,
        [childId, e.at, e.kind, e.detail, e.durationMin]);
    },
    async listNewbornEvents(userId, limit) {
      const { rows } = await pool.query(
        `SELECT c.id AS child_id, c.name AS child_name, e.at, e.kind, e.detail, e.duration_min
         FROM children c JOIN newborn_events e ON e.child_id = c.id
         WHERE c.guardian_id = $1 ORDER BY e.at DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({
        childId: r.child_id, childName: r.child_name, at: new Date(r.at).toISOString(),
        kind: r.kind, detail: r.detail, durationMin: r.duration_min,
      }));
    },

    async upsertChildEmergency(childId, m) {
      await pool.query(
        `INSERT INTO child_emergency (child_id, blood_type, allergies, conditions, medications,
                                      doctor_name, doctor_phone, contact_name, contact_phone, notes)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         ON CONFLICT (child_id) DO UPDATE SET
           blood_type = EXCLUDED.blood_type, allergies = EXCLUDED.allergies,
           conditions = EXCLUDED.conditions, medications = EXCLUDED.medications,
           doctor_name = EXCLUDED.doctor_name, doctor_phone = EXCLUDED.doctor_phone,
           contact_name = EXCLUDED.contact_name, contact_phone = EXCLUDED.contact_phone,
           notes = EXCLUDED.notes`,
        [childId, m.bloodType, m.allergies, m.conditions, m.medications,
          m.doctorName, m.doctorPhone, m.contactName, m.contactPhone, m.notes]);
    },
    async listMedicalIds(userId) {
      const { rows } = await pool.query(
        `SELECT c.id AS child_id, c.name AS child_name, e.blood_type, e.allergies, e.conditions,
                e.medications, e.doctor_name, e.doctor_phone, e.contact_name, e.contact_phone, e.notes
         FROM children c JOIN child_emergency e ON e.child_id = c.id
         WHERE c.guardian_id = $1 ORDER BY c.name`, [userId]);
      return rows.map((r) => ({
        childId: r.child_id, childName: r.child_name,
        bloodType: r.blood_type ?? '', allergies: r.allergies ?? '', conditions: r.conditions ?? '',
        medications: r.medications ?? '', doctorName: r.doctor_name ?? '', doctorPhone: r.doctor_phone ?? '',
        contactName: r.contact_name ?? '', contactPhone: r.contact_phone ?? '', notes: r.notes ?? '',
      }));
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

    // ---- Admin ----
    async adminStats() {
      const [users, devices, alerts, ingest] = await Promise.all([
        pool.query(`SELECT count(*)::int AS n FROM users`),
        pool.query(`SELECT count(*)::int AS n FROM devices`),
        pool.query(`SELECT count(*)::int AS n FROM pregnancy_health_metrics WHERE triage_severity='emergency' AND recorded_at > now() - interval '1 day'`),
        pool.query(`SELECT count(*)::int AS n FROM pregnancy_health_metrics WHERE recorded_at > now() - interval '1 hour'`),
      ]);
      return { activeUsers: users.rows[0].n, devicesOnline: devices.rows[0].n, alertsToday: alerts.rows[0].n, ingestLastHour: ingest.rows[0].n };
    },
    async childrenStats(asOf) {
      const { rows } = await pool.query(
        `SELECT gender, date_of_birth FROM children`);
      return computeChildrenStats(
        rows.map((r) => ({ gender: r.gender ?? null, dateOfBirth: r.date_of_birth ? new Date(r.date_of_birth).toISOString() : null })),
        asOf,
      );
    },
    async recentEmergencies(limit) {
      const { rows } = await pool.query(
        `SELECT m.user_id, u.display_name, m.triage_severity, m.recorded_at
         FROM pregnancy_health_metrics m JOIN users u ON u.id = m.user_id
         WHERE m.triage_severity = 'emergency' ORDER BY m.recorded_at DESC LIMIT $1`, [limit]);
      // The hypertable has no single-column id, so an emergency's identity is
      // (user, time). Compute it here so it matches between the list and the ack.
      const emergencies = rows.map((r) => ({
        id: `${r.user_id}|${new Date(r.recorded_at).toISOString()}`,
        userId: r.user_id as string,
        displayName: r.display_name as string,
        code: 'EMERGENCY',
        severity: r.triage_severity as string,
        at: new Date(r.recorded_at).toISOString(),
      }));
      const ids = emergencies.map((e) => e.id);
      const acks = ids.length
        ? (await pool.query(
            `SELECT emergency_id, staff_id, acknowledged_at FROM emergency_acks WHERE emergency_id = ANY($1)`,
            [ids])).rows
        : [];
      const byId = new Map(acks.map((a) => [a.emergency_id as string, a]));
      return emergencies.map((e) => {
        const a = byId.get(e.id);
        return {
          ...e,
          acknowledgedAt: a ? new Date(a.acknowledged_at).toISOString() : null,
          acknowledgedBy: a ? (a.staff_id as string) : null,
        };
      });
    },
    async acknowledgeEmergency(id, staffId, at) {
      const { rowCount } = await pool.query(
        `INSERT INTO emergency_acks (emergency_id, staff_id, acknowledged_at)
         VALUES ($1,$2,$3) ON CONFLICT (emergency_id) DO NOTHING`,
        [id, staffId, at]);
      return (rowCount ?? 0) > 0;
    },
    async adminListUsers(q, limit, offset) {
      const like = `%${q}%`;
      const total = await pool.query(
        `SELECT count(*)::int AS n FROM users WHERE display_name ILIKE $1 OR email ILIKE $1`, [like]);
      const { rows } = await pool.query(
        `SELECT id, display_name, phone_e164, due_date FROM users
         WHERE display_name ILIKE $1 OR email ILIKE $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
        [like, limit, offset]);
      return {
        total: total.rows[0].n,
        users: rows.map((r) => ({ id: r.id, displayName: r.display_name, phone: r.phone_e164, dueDate: r.due_date })),
      };
    },
    async adminUserHealth(userId) {
      const latest = await pool.query(
        `SELECT heart_rate_bpm, spo2_pct, systolic_mmhg, diastolic_mmhg, core_temp_c
         FROM pregnancy_health_metrics WHERE user_id = $1 ORDER BY recorded_at DESC LIMIT 1`, [userId]);
      if (latest.rows.length === 0) return null;
      const r = latest.rows[0];
      const triage = await pool.query(
        `SELECT triage_severity, recorded_at FROM pregnancy_health_metrics
         WHERE user_id = $1 AND triage_severity IN ('warning','emergency') ORDER BY recorded_at DESC LIMIT 20`, [userId]);
      return {
        latest: { hr: r.heart_rate_bpm, spo2: r.spo2_pct, systolic: r.systolic_mmhg, diastolic: r.diastolic_mmhg, temp: r.core_temp_c },
        triage: triage.rows.map((t) => ({ code: t.triage_severity, severity: t.triage_severity, at: new Date(t.recorded_at).toISOString() })),
      };
    },
    async writeAudit(entry) {
      await pool.query(`INSERT INTO audit_log (staff_id, action, target) VALUES ($1,$2,$3)`,
        [entry.staffId, entry.action, entry.target ?? null]);
    },
    async listAudit(limit) {
      const { rows } = await pool.query(`SELECT staff_id, action, target, at FROM audit_log ORDER BY at DESC LIMIT $1`, [limit]);
      return rows.map((r) => ({ staffId: r.staff_id, action: r.action, target: r.target, at: new Date(r.at).toISOString() }));
    },

    // ---- Back-office drilldowns ----
    async adminUserDetail(userId) {
      const { rows: prof } = await pool.query(
        `SELECT display_name, phone, due_date, locale, birth_date, city FROM users WHERE id = $1`, [userId]);
      if (!prof[0]) return null;
      const [kids, devs, alerts, sleepCount, dayCount] = await Promise.all([
        pool.query(
          `SELECT c.id, c.name, c.date_of_birth,
                  (SELECT count(*) FROM geofences g WHERE g.child_id = c.id) AS zones
             FROM children c WHERE c.guardian_id = $1 ORDER BY c.name`, [userId]),
        pool.query(
          `SELECT id, name, kind, child_id, battery_pct FROM devices WHERE user_id = $1 ORDER BY name`, [userId]),
        pool.query(
          `SELECT a.kind, a.zone_name, a.at, c.name AS child_name
             FROM safety_alerts a LEFT JOIN children c ON c.id = a.child_id
            WHERE a.user_id = $1 ORDER BY a.at DESC LIMIT 20`, [userId]),
        pool.query(`SELECT count(*) AS n FROM sleep_nights WHERE user_id = $1`, [userId]),
        pool.query(`SELECT count(*) AS n FROM cycle_day_logs WHERE user_id = $1`, [userId]),
      ]);
      const health = await this.adminUserHealth(userId);
      return {
        id: userId,
        displayName: prof[0].display_name ?? '',
        phone: prof[0].phone ?? null,
        dueDate: prof[0].due_date ? new Date(prof[0].due_date).toISOString().slice(0, 10) : null,
        locale: prof[0].locale ?? null,
        birthDate: prof[0].birth_date ? new Date(prof[0].birth_date).toISOString().slice(0, 10) : null,
        city: prof[0].city ?? null,
        children: kids.rows.map((r) => ({
          id: r.id,
          name: r.name,
          dateOfBirth: r.date_of_birth ? new Date(r.date_of_birth).toISOString().slice(0, 10) : null,
          zones: Number(r.zones ?? 0),
        })),
        devices: devs.rows.map((r) => ({
          id: r.id, name: r.name, kind: r.kind, childId: r.child_id,
          batteryPct: r.battery_pct === null ? null : Number(r.battery_pct),
        })),
        latest: health?.latest ?? {},
        triage: health?.triage ?? [],
        alerts: alerts.rows.map((r) => ({
          kind: r.kind, childName: r.child_name ?? '', zoneName: r.zone_name,
          at: new Date(r.at).toISOString(),
        })),
        sleepNights: Number(sleepCount.rows[0]?.n ?? 0),
        loggedDays: Number(dayCount.rows[0]?.n ?? 0),
      };
    },

    async adminDevices(limit) {
      const { rows } = await pool.query(
        `SELECT d.id, d.name, d.kind, d.user_id, d.battery_pct, d.last_seen,
                u.display_name, c.name AS child_name
           FROM devices d
           JOIN users u ON u.id = d.user_id
           LEFT JOIN children c ON c.id = d.child_id
          ORDER BY d.last_seen DESC NULLS LAST LIMIT $1`, [limit]);
      return rows.map((r) => ({
        id: r.id, name: r.name, kind: r.kind, userId: r.user_id,
        displayName: r.display_name ?? '', childName: r.child_name ?? null,
        batteryPct: r.battery_pct === null ? null : Number(r.battery_pct),
        lastSeen: r.last_seen ? new Date(r.last_seen).toISOString() : null,
      }));
    },

    async adminSafetyEvents(limit) {
      const { rows } = await pool.query(
        `SELECT a.user_id, a.kind, a.zone_name, a.at, u.display_name, c.name AS child_name
           FROM safety_alerts a
           JOIN users u ON u.id = a.user_id
           LEFT JOIN children c ON c.id = a.child_id
          ORDER BY a.at DESC LIMIT $1`, [limit]);
      return rows.map((r) => ({
        userId: r.user_id, displayName: r.display_name ?? '',
        childName: r.child_name ?? '', kind: r.kind, zoneName: r.zone_name,
        at: new Date(r.at).toISOString(),
      }));
    },

    /**
     * Product metrics from real rows.
     *
     * "Active" is the union of the things a user can actually do: record a
     * reading, generate a safety alert, or have their child's tracker report a
     * position. Deliberately not "opened the app" — there is no session table,
     * and inventing one from request logs would count a background sync as
     * engagement.
     *
     * The heavy lifting stays in SQL (these tables are hypertables and the row
     * counts get large), but the definitions match analytics/biMetrics.ts
     * exactly — UTC day buckets, windows inclusive of today, day-N retention
     * aggregated across every cohort whose day N has arrived.
     */
    async deleteAccount(userId) {
      // One statement is enough: every table that references users(id) is
      // declared ON DELETE CASCADE in schema.sql, so her readings, children,
      // their locations and their geofences go with the row. A hand-written
      // list of tables to clear would fall behind the schema the first time
      // someone adds one — and the failure would be silent, leaving orphaned
      // health data behind after she was told it was erased.
      const { rowCount } = await pool.query('DELETE FROM users WHERE id = $1', [userId]);
      return (rowCount ?? 0) > 0;
    },

    /**
     * Product metrics, computed by the same code the in-memory repository uses.
     *
     * This used to be a second implementation in SQL: every window, cohort and
     * ratio expressed twice, once here and once in biMetrics.ts. That file's
     * own header warned the two WOULD drift, and they already had — retention
     * here covered only d1/d7/d30 because a curve is tedious in SQL, and the
     * event mix silently reported chat and SOS as zero.
     *
     * So SQL does what SQL is for — pulling the rows — and the arithmetic
     * happens in one tested place. What ships to the dashboard is then the
     * same number regardless of which repository answered.
     *
     * The window is bounded: a metric on this dashboard reaches back 60 days at
     * most (30 of history plus the 30 before it that growth accounting compares
     * against), so there is no reason to read further. At MVP scale that is a
     * few hundred thousand rows at worst. If the base outgrows it, the fix is a
     * daily rollup table feeding the same function — not a second copy of these
     * definitions.
     */
    async adminBiMetrics() {
      const HISTORY_DAYS = 60;
      const since = `now() - interval '${HISTORY_DAYS} days'`;

      const [users, events, devices] = await Promise.all([
        pool.query(`SELECT id, created_at FROM users`),
        pool.query(`
          SELECT user_id, recorded_at AS at, 'telemetry' AS kind
            FROM pregnancy_health_metrics WHERE recorded_at > ${since}
          UNION ALL
          SELECT c.guardian_id, l.observed_at, 'location'
            FROM location_history l JOIN children c ON c.id = l.child_id
           WHERE l.observed_at > ${since}
          UNION ALL
          -- An SOS is an alert too: it is one of the rows a parent sees in the
          -- alert list. Counting it only as an SOS would make the alert total
          -- on this dashboard disagree with the list in the app.
          SELECT user_id, at, 'alert' FROM safety_alerts WHERE at > ${since}
          UNION ALL
          SELECT user_id, at, 'sos' FROM safety_alerts
           WHERE kind = 'sos' AND at > ${since}`),
        pool.query(`
          SELECT count(*) AS total,
                 count(*) FILTER (WHERE last_seen > now() - interval '15 minutes') AS online
            FROM devices`),
      ]);

      const dv = devices.rows[0] ?? {};
      return computeBiMetrics({
        users: users.rows.map((r) => ({
          id: String(r.id),
          createdAt: new Date(r.created_at as string).toISOString(),
        })),
        events: events.rows.map((r) => ({
          userId: String(r.user_id),
          at: new Date(r.at as string).toISOString(),
          kind: r.kind as BiEventKind,
        })),
        devices: { total: Number(dv.total ?? 0), online: Number(dv.online ?? 0) },
        now: new Date(),
      });
    },

    async adminAnalytics() {
      const { rows } = await pool.query(`
        SELECT (SELECT count(*) FROM users) AS total_users,
               (SELECT count(*) FROM users WHERE due_date IS NOT NULL) AS pregnant,
               (SELECT count(DISTINCT guardian_id) FROM children) AS with_children,
               (SELECT count(*) FROM devices) AS devices,
               (SELECT count(*) FROM safety_alerts WHERE at > now() - interval '7 days') AS alerts_7d,
               (SELECT count(*) FROM safety_alerts WHERE kind = 'sos') AS sos_all_time`);
      const r = rows[0] ?? {};
      const catalog = await this.contentCatalog();
      let items = 0, linked = 0;
      for (const list of Object.values(catalog)) {
        items += list.length;
        linked += list.filter((i) => (i.url ?? '').trim().length > 0).length;
      }
      return {
        totalUsers: Number(r.total_users ?? 0),
        pregnant: Number(r.pregnant ?? 0),
        withChildren: Number(r.with_children ?? 0),
        devices: Number(r.devices ?? 0),
        alerts7d: Number(r.alerts_7d ?? 0),
        sosAllTime: Number(r.sos_all_time ?? 0),
        stageDistribution: {},
        contentStages: Object.keys(catalog).length,
        contentItems: items,
        contentLinked: linked,
      };
    },

    // ---- Timeline content ----
    async contentCatalog() {
      const { rows } = await pool.query(
        `SELECT stage_key, payload FROM timeline_content ORDER BY stage_key`);
      const out: Record<string, ContentItemRow[]> = {};
      for (const r of rows) {
        out[r.stage_key] = Array.isArray(r.payload) ? r.payload : [];
      }
      return out;
    },

    async putStageContent(stageKey, items) {
      if (items.length === 0) {
        await pool.query(`DELETE FROM timeline_content WHERE stage_key = $1`, [stageKey]);
        return;
      }
      await pool.query(
        `INSERT INTO timeline_content (stage_key, payload, updated_at)
         VALUES ($1, $2::jsonb, now())
         ON CONFLICT (stage_key) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now()`,
        [stageKey, JSON.stringify(items)]);
    },

    // ---- Sleep ----
    async recordSleep(userId, s) {
      await pool.query(
        `INSERT INTO sleep_nights (user_id, night, deep_min, rem_min, light_min, awake_min)
         VALUES ($1,$2,$3,$4,$5,$6)
         ON CONFLICT (user_id, night) DO UPDATE
           SET deep_min = EXCLUDED.deep_min, rem_min = EXCLUDED.rem_min,
               light_min = EXCLUDED.light_min, awake_min = EXCLUDED.awake_min`,
        [userId, s.night, s.deepMin, s.remMin, s.lightMin, s.awakeMin]);
    },
    async listSleep(userId, limit) {
      const { rows } = await pool.query(
        `SELECT night, deep_min, rem_min, light_min, awake_min FROM sleep_nights
         WHERE user_id = $1 ORDER BY night DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({
        night: new Date(r.night).toISOString(),
        deepMin: r.deep_min, remMin: r.rem_min, lightMin: r.light_min, awakeMin: r.awake_min,
      }));
    },

    // ---- Maternal weight log ----
    async recordWeight(userId, w) {
      await pool.query(
        `INSERT INTO weight_entries (user_id, log_date, kg)
         VALUES ($1,$2,$3)
         ON CONFLICT (user_id, log_date) DO UPDATE SET kg = EXCLUDED.kg`,
        [userId, w.date, w.kg]);
    },
    async listWeight(userId, limit) {
      const { rows } = await pool.query(
        `SELECT log_date, kg FROM weight_entries
         WHERE user_id = $1 ORDER BY log_date DESC LIMIT $2`, [userId, limit]);
      // NUMERIC comes back as a string; the date as a Date — normalise both.
      return rows.map((r) => ({ date: new Date(r.log_date).toISOString().slice(0, 10), kg: Number(r.kg) }));
    },

    // ---- Pregnancy timed sessions (upsert on ended_at) ----
    async recordKickSession(userId, s) {
      await pool.query(
        `INSERT INTO kick_sessions (user_id, ended_at, count, duration_sec)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (user_id, ended_at) DO UPDATE SET count = EXCLUDED.count, duration_sec = EXCLUDED.duration_sec`,
        [userId, s.endedAt, s.count, s.durationSec]);
    },
    async listKickSessions(userId, limit) {
      const { rows } = await pool.query(
        `SELECT ended_at, count, duration_sec FROM kick_sessions
         WHERE user_id = $1 ORDER BY ended_at DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({ endedAt: new Date(r.ended_at).toISOString(), count: r.count, durationSec: r.duration_sec }));
    },
    async recordContractionSession(userId, s) {
      await pool.query(
        `INSERT INTO contraction_sessions (user_id, ended_at, count, avg_duration_sec, avg_interval_sec)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (user_id, ended_at) DO UPDATE
           SET count = EXCLUDED.count, avg_duration_sec = EXCLUDED.avg_duration_sec, avg_interval_sec = EXCLUDED.avg_interval_sec`,
        [userId, s.endedAt, s.count, s.avgDurationSec, s.avgIntervalSec]);
    },
    async listContractionSessions(userId, limit) {
      const { rows } = await pool.query(
        `SELECT ended_at, count, avg_duration_sec, avg_interval_sec FROM contraction_sessions
         WHERE user_id = $1 ORDER BY ended_at DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({
        endedAt: new Date(r.ended_at).toISOString(), count: r.count,
        avgDurationSec: r.avg_duration_sec, avgIntervalSec: r.avg_interval_sec,
      }));
    },

    // ---- Women's-health day logs ----
    async upsertDayLog(userId, log) {
      await pool.query(
        `INSERT INTO cycle_day_logs (user_id, log_date, mood, symptoms, kicks, flow)
         VALUES ($1,$2,$3,$4,$5,$6)
         ON CONFLICT (user_id, log_date) DO UPDATE
           SET mood = EXCLUDED.mood, symptoms = EXCLUDED.symptoms,
               kicks = EXCLUDED.kicks, flow = EXCLUDED.flow`,
        [userId, log.date, log.mood, log.symptoms, log.kicks, log.flow]);
    },
    async listDayLogs(userId, from, to) {
      const { rows } = await pool.query(
        `SELECT log_date, mood, symptoms, kicks, flow FROM cycle_day_logs
         WHERE user_id = $1 AND log_date BETWEEN $2 AND $3 ORDER BY log_date`, [userId, from, to]);
      return rows.map((r) => ({
        date: r.log_date, mood: r.mood, symptoms: r.symptoms ?? [], kicks: r.kicks, flow: r.flow,
      }));
    },

    // ---- Safety alerts ----
    async recordAlert(userId, a) {
      await pool.query(
        `INSERT INTO safety_alerts (user_id, child_id, kind, zone_name, at) VALUES ($1,$2,$3,$4,$5)`,
        [userId, a.childId, a.kind, a.zoneName, a.at]);
    },
    async listAlerts(userId, limit) {
      const { rows } = await pool.query(
        `SELECT child_id, kind, zone_name, at FROM safety_alerts
         WHERE user_id = $1 ORDER BY at DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({
        childId: r.child_id, kind: r.kind, zoneName: r.zone_name, at: new Date(r.at).toISOString(),
      }));
    },

    // ---- Profile ----
    async getProfile(userId) {
      const { rows } = await pool.query(
        `SELECT display_name, phone_e164, due_date, locale, birth_date, city
           FROM users WHERE id = $1`, [userId]);
      if (rows.length === 0) return null;
      const r = rows[0];
      return {
        displayName: r.display_name,
        phone: r.phone_e164,
        dueDate: r.due_date ? new Date(r.due_date).toISOString().slice(0, 10) : null,
        locale: r.locale,
        birthDate: r.birth_date ? new Date(r.birth_date).toISOString().slice(0, 10) : null,
        city: r.city ?? null,
      };
    },
    async upsertProfile(userId, p) {
      // The user row exists from signup (email is required); this updates it.
      await pool.query(
        `UPDATE users SET display_name = $2, phone_e164 = $3, due_date = $4,
                          locale = COALESCE($5, locale),
                          birth_date = $6, city = $7, updated_at = now()
         WHERE id = $1`,
        [userId, p.displayName, p.phone, p.dueDate, p.locale, p.birthDate, p.city]);
    },

    // ---- Device reassignment ----
    async reassignDevice(deviceId, childId) {
      await pool.query(`UPDATE devices SET child_id = $2 WHERE id = $1`, [deviceId, childId]);
    },
  };
}
