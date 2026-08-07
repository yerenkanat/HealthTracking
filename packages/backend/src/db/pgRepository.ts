/**
 * Postgres-backed Repository (TimescaleDB + PostGIS). Uses `pg`.
 * Geo queries mirror the examples in db/schema.sql. Kept thin: parameterised SQL,
 * no ORM. Health/location columns should be envelope-encrypted at the app layer
 * before reaching here in production (Data Privacy Officer).
 */

import { Pool } from 'pg';
import { computeChildrenStats } from '../analytics/childStats.js';
import { MAX_CODE_ATTEMPTS } from '../routes/phoneAuth.js';
import { normalizeSerial } from '../deviceSerial.js';
import type { ContentItemRow, DeviceRegistryRow, InventoryProduct, ShopProduct } from './repository';
import type {
  BandTelemetry,
  BpCalibration,
  ChildLocationFix,
  Geofence,
  GeofenceEvent,
  TriageSeverity,
} from '@fcs/shared';
import type { Repository } from './repository';
import { bundleDiscountMinor } from './repository';
import { normalizePhone } from '../phone.js';
import { computeBiMetrics, type BiEventKind } from '../analytics/biMetrics.js';


/**
 * Does this look like a UUID?
 *
 * Every ownership check below compares a CLIENT-SUPPLIED id against a UUID
 * column. Postgres parses the parameter before it compares anything, so an id
 * that is not a UUID raises 22P02 (invalid_text_representation) — an exception,
 * not an empty result. Nothing caught it, so the answer to "may I see this
 * child's location" was a 500.
 *
 * Two things made that worse than a stray error. It is reachable by anyone:
 * any string in the path 500s the API. And it is reached constantly by our own
 * app, which creates children locally during onboarding with ids like
 * `child-1` and polls for their location every few seconds — a fresh install
 * signed in against production is a 500 generator.
 *
 * A malformed id is not a server fault. It is an id we do not have, and these
 * lookups now say so.
 */
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function looksLikeUuid(id: unknown): boolean {
  return typeof id === 'string' && UUID_RE.test(id);
}

/** One device_registry row, in the shape the interface promises. */
function toRegistryRow(r: Record<string, unknown>): DeviceRegistryRow {
  return {
    serial: String(r.serial),
    status: r.status as DeviceRegistryRow['status'],
    kind: (r.kind ?? null) as DeviceRegistryRow['kind'],
    activationCode: (r.activation_code ?? null) as string | null,
    orderId: (r.order_id ?? null) as string | null,
    receivedAt: new Date(r.received_at as string).toISOString(),
    activatedByPhone: (r.activated_by_phone ?? null) as string | null,
    activatedAt: r.activated_at ? new Date(r.activated_at as string).toISOString() : null,
    note: (r.note ?? null) as string | null,
  };
}

export function createPgRepository(pool: Pool): Repository {
  /**
   * The `devices.id` UUID behind a physical device id, or null.
   *
   * Telemetry names the band by what is printed on it; the metrics table
   * references devices by their row id. Null for a manual reading (no device)
   * and for a band that has not been registered — both of which the column
   * allows, so a reading is kept even when we cannot say which band took it.
   */
  async function deviceRowId(userId: string, deviceId: string | undefined): Promise<string | null> {
    if (!deviceId) return null;
    const { rows } = await pool.query(
      'SELECT id FROM devices WHERE user_id = $1 AND ble_mac = $2', [userId, deviceId]);
    return rows[0]?.id ?? null;
  }

  return {
    async insertHealthMetric(m: BandTelemetry & { userId: string; triageSeverity: TriageSeverity }) {
      // ON CONFLICT DO NOTHING against the phm_unique_reading constraint makes a
      // resend a no-op instead of a duplicate row. rowCount is 0 when the row was
      // already there, which is how the caller learns not to push the emergency
      // (or count the reading) a second time.
      const res = await pool.query(
        `INSERT INTO pregnancy_health_metrics
           (device_id, user_id, recorded_at, core_temp_c, skin_temp_c, heart_rate_bpm,
            spo2_pct, systolic_mmhg, diastolic_mmhg, glucose_mmol, during_sleep, triage_severity)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
         ON CONFLICT (user_id, device_id, recorded_at) DO NOTHING`,
        [
          // A manual reading carries deviceId '' (no device); store it as NULL so
          // it satisfies the FK and the nullable column, instead of failing the
          // uuid cast.
          //
          // A band sends its PHYSICAL id — a MAC — and this column is the UUID
          // primary key of `devices`, so writing it straight in raised 22P02
          // and every reading from a real band was a 500. Resolved through
          // ble_mac; unknown device → NULL, which the column allows and which
          // reads as "we have this reading but not which band took it" rather
          // than losing it.
          await deviceRowId(m.userId, m.deviceId), m.userId, m.recordedAt, m.coreTempC ?? null, m.skinTempC ?? null,
          m.heartRateBpm ?? null, m.spo2Pct ?? null, m.systolicMmHg ?? null,
          m.diastolicMmHg ?? null, m.glucoseMmol ?? null, m.duringSleep ?? false, m.triageSeverity,
        ],
      );
      return (res.rowCount ?? 0) === 0; // true = duplicate (nothing inserted)
    },

    async listManualVitals(userId) {
      const { rows } = await pool.query(
        `SELECT recorded_at, heart_rate_bpm, spo2_pct, systolic_mmhg, diastolic_mmhg, core_temp_c, glucose_mmol
         FROM pregnancy_health_metrics
         WHERE user_id = $1 AND device_id IS NULL
         ORDER BY recorded_at DESC LIMIT 200`,
        [userId],
      );
      return rows.map((r) => ({
        recordedAt: new Date(r.recorded_at).toISOString(),
        heartRateBpm: r.heart_rate_bpm, spo2Pct: r.spo2_pct, systolicMmHg: r.systolic_mmhg,
        diastolicMmHg: r.diastolic_mmhg, coreTempC: r.core_temp_c, glucoseMmol: r.glucose_mmol,
      }));
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
    async latestBpCalibration(userId) {
      // idx_bpcal_user_time makes this an index scan of one row.
      const { rows } = await pool.query(
        `SELECT measured_at, cuff_systolic, cuff_diastolic, ppg_systolic, ppg_diastolic,
                systolic_offset, diastolic_offset
         FROM bp_calibration WHERE user_id = $1 ORDER BY measured_at DESC LIMIT 1`, [userId]);
      const r = rows[0];
      if (!r) return null;
      return {
        systolicOffset: Number(r.systolic_offset),
        diastolicOffset: Number(r.diastolic_offset),
        calibratedAt: new Date(r.measured_at).toISOString(),
        cuffSystolic: Number(r.cuff_systolic),
        cuffDiastolic: Number(r.cuff_diastolic),
        ppgSystolic: Number(r.ppg_systolic),
        ppgDiastolic: Number(r.ppg_diastolic),
      };
    },

    async loadGeofences(childId): Promise<Geofence[]> {
      const { rows } = await pool.query(
        `SELECT id, name, shape, radius_m,
                center_lat AS clat, center_lng AS clng, area_geojson
         FROM geofences WHERE child_id = $1`,
        [childId],
      );
      return rows.map((r): Geofence => {
        if (r.shape === 'circle') {
          return { id: r.id, name: r.name, shape: 'circle', center: { lat: r.clat, lng: r.clng }, radiusM: r.radius_m };
        }
        // area_geojson is jsonb → the driver returns it already parsed.
        const ring = (r.area_geojson as { coordinates: [number, number][][] }).coordinates[0];
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
        `INSERT INTO location_history (child_id, observed_at, lat, lng, source, accuracy_m)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [fix.childId, fix.observedAt, fix.coords.lat, fix.coords.lng, fix.source, fix.coords.accuracyM ?? null],
      );
    },

    async lastLocation(childId) {
      const { rows } = await pool.query(
        `SELECT child_id, observed_at, lat, lng, source, accuracy_m
           FROM location_history
          WHERE child_id = $1
          ORDER BY observed_at DESC
          LIMIT 1`,
        [childId],
      );
      const r = rows[0];
      if (!r) return null;
      return {
        childId: r.child_id,
        observedAt: new Date(r.observed_at).toISOString(),
        source: r.source,
        coords: {
          lat: Number(r.lat),
          lng: Number(r.lng),
          // Nullable in the table; the type wants it absent, not null.
          ...(r.accuracy_m === null ? {} : { accuracyM: Number(r.accuracy_m) }),
        },
      } as ChildLocationFix;
    },

    // ---- App sign-in (phone number) ----
    async userByPhone(phone) {
      const { rows } = await pool.query(
        'SELECT id, display_name FROM users WHERE phone_e164 = $1', [phone]);
      return rows[0] ? { id: rows[0].id, displayName: rows[0].display_name } : null;
    },

    async createUserWithPhone(a) {
      // ON CONFLICT so two taps of the button in quick succession — which a
      // slow connection invites — cannot create two accounts for one number.
      const { rows } = await pool.query(
        `INSERT INTO users (phone_e164, display_name)
         VALUES ($1, $2)
         ON CONFLICT (phone_e164) WHERE phone_e164 IS NOT NULL
         DO UPDATE SET phone_e164 = EXCLUDED.phone_e164
         RETURNING id, display_name`,
        [a.phone, a.displayName],
      );
      return { id: rows[0].id, displayName: rows[0].display_name };
    },

    async createUserSession(s) {
      await pool.query(
        `INSERT INTO user_sessions (token_hash, user_id, expires_at, user_agent)
         VALUES ($1,$2,$3,$4)`,
        [s.tokenHash, s.userId, s.expiresAt, s.userAgent.slice(0, 300)],
      );
      await pool.query('DELETE FROM user_sessions WHERE expires_at < now()');
    },

    async userBySessionToken(tokenHash) {
      const { rows } = await pool.query(
        `SELECT user_id FROM user_sessions WHERE token_hash = $1 AND expires_at > now()`,
        [tokenHash],
      );
      return rows[0] ? { userId: rows[0].user_id } : null;
    },

    async deleteUserSession(tokenHash) {
      await pool.query('DELETE FROM user_sessions WHERE token_hash = $1', [tokenHash]);
    },

    async recentPhoneClaims(phone, since) {
      const { rows } = await pool.query(
        'SELECT count(*)::int AS n FROM user_login_attempts WHERE phone = $1 AND at >= $2',
        [phone, since],
      );
      return rows[0]?.n ?? 0;
    },

    // ---- Which devices are ours ----
    async deviceRegistryEntry(serial) {
      const { rows } = await pool.query(
        `SELECT serial, status, kind, activation_code, order_id, received_at,
                activated_by_phone, activated_at, note
           FROM device_registry WHERE serial = $1`,
        [normalizeSerial(serial)]);
      return rows[0] ? toRegistryRow(rows[0]) : null;
    },

    async addDeviceSerials(rows) {
      let added = 0;
      for (const r of rows) {
        const serial = normalizeSerial(r.serial);
        if (!serial) continue;
        // DO NOTHING, not DO UPDATE: receiving the same shipment twice must not
        // reset a unit that has already been sold back to stock, which would
        // hand it to whoever pairs it next.
        const res = await pool.query(
          `INSERT INTO device_registry (serial, kind, activation_code, note, added_by)
           VALUES ($1,$2,$3,$4,$5) ON CONFLICT (serial) DO NOTHING`,
          [serial, r.kind ?? null, r.activationCode ?? null, r.note ?? null, r.addedBy ?? null]);
        if (res.rowCount) added += 1;
      }
      return { added, skipped: rows.length - added };
    },

    async markDeviceActivated(serial, phone) {
      // Only from `stock`, and only when unclaimed. That WHERE clause is what
      // makes an activation code single-use: the second redemption changes no
      // rows and comes back false.
      const res = await pool.query(
        `UPDATE device_registry
            SET status = 'sold', activated_by_phone = $2, activated_at = now()
          WHERE serial = $1
            AND status = 'stock'
            AND activated_by_phone IS NULL`,
        [normalizeSerial(serial), phone]);
      if (res.rowCount) return true;
      // Already hers is success — re-pairing after a reinstall must work.
      const { rows } = await pool.query(
        'SELECT activated_by_phone FROM device_registry WHERE serial = $1',
        [normalizeSerial(serial)]);
      return rows[0]?.activated_by_phone === phone;
    },

    async setDeviceRegistryStatus(serial, status) {
      await pool.query(
        'UPDATE device_registry SET status = $2 WHERE serial = $1',
        [normalizeSerial(serial), status]);
    },

    async assignDevicesToOrder(orderId, serials) {
      const linked: string[] = [];
      const unknown: string[] = [];
      for (const raw of serials) {
        const serial = normalizeSerial(raw);
        if (!serial) continue;
        const res = await pool.query(
          'UPDATE device_registry SET order_id = $2 WHERE serial = $1', [serial, orderId]);
        // A serial we do not recognise is reported back, not swallowed: it is
        // almost always a typo on the packing slip, and finding that out at
        // dispatch is the difference between a correction and a support case.
        (res.rowCount ? linked : unknown).push(serial);
      }
      return { linked, unknown };
    },

    async devicesForOrder(orderId) {
      const { rows } = await pool.query(
        `SELECT serial, status, kind, activation_code, order_id, received_at,
                activated_by_phone, activated_at, note
           FROM device_registry WHERE order_id = $1 ORDER BY serial`, [orderId]);
      return rows.map(toRegistryRow);
    },

    async listDeviceRegistry(limit) {
      const { rows } = await pool.query(
        `SELECT serial, status, kind, activation_code, order_id, received_at,
                activated_by_phone, activated_at, note
           FROM device_registry ORDER BY received_at DESC LIMIT $1`, [limit]);
      return rows.map(toRegistryRow);
    },

    async deviceByActivationCode(code) {
      const c = normalizeSerial(code);
      if (!c) return null;
      const { rows } = await pool.query(
        `SELECT serial, status, kind, activation_code, order_id, received_at,
                activated_by_phone, activated_at, note
           FROM device_registry WHERE activation_code = $1`, [c]);
      return rows[0] ? toRegistryRow(rows[0]) : null;
    },

    async recordPhoneClaim(phone) {
      await pool.query('INSERT INTO user_login_attempts (phone) VALUES ($1)', [phone]);
    },

    async putPhoneCode(c) {
      // One live code per number. Asking for a second invalidates the first, so
      // a code somebody read over her shoulder stops working the moment she
      // asks again.
      await pool.query(
        `INSERT INTO phone_codes (phone, code_hash, expires_at, attempts, created_at)
         VALUES ($1,$2,$3,0,now())
         ON CONFLICT (phone) DO UPDATE SET
           code_hash = EXCLUDED.code_hash,
           expires_at = EXCLUDED.expires_at,
           attempts = 0,
           created_at = now()`,
        [c.phone, c.codeHash, c.expiresAt]);
    },

    async usePhoneCode(phone, codeHash, now) {
      const { rows } = await pool.query(
        'SELECT code_hash, expires_at, attempts FROM phone_codes WHERE phone = $1', [phone]);
      const row = rows[0];
      if (!row) return 'none';
      if (row.attempts >= MAX_CODE_ATTEMPTS) return 'too_many';
      if (new Date(row.expires_at) <= now) return 'expired';
      if (row.code_hash !== codeHash) {
        // Count the miss BEFORE answering, so a bot cannot outrun the counter
        // by firing guesses in parallel.
        await pool.query(
          'UPDATE phone_codes SET attempts = attempts + 1 WHERE phone = $1', [phone]);
        return 'wrong';
      }
      // Consumed: a correct code is worth exactly one sign-in.
      await pool.query('DELETE FROM phone_codes WHERE phone = $1', [phone]);
      return 'ok';
    },

    // ---- Staff sign-in ----
    async staffByPhone(phone) {
      const { rows } = await pool.query(
        `SELECT id, phone, password_hash, role, display_name, disabled_at
           FROM staff_accounts WHERE phone = $1`,
        [phone],
      );
      const r = rows[0];
      if (!r) return null;
      return {
        id: r.id,
        phone: r.phone,
        passwordHash: r.password_hash,
        role: r.role,
        displayName: r.display_name,
        disabled: r.disabled_at !== null,
      };
    },

    async staffById(id) {
      const { rows } = await pool.query(
        `SELECT id, phone, password_hash, role, display_name, disabled_at
           FROM staff_accounts WHERE id = $1`,
        [id],
      );
      const r = rows[0];
      if (!r) return null;
      return {
        id: r.id,
        phone: r.phone,
        passwordHash: r.password_hash,
        role: r.role,
        displayName: r.display_name,
        disabled: r.disabled_at !== null,
      };
    },

    async upsertStaffAccount(a) {
      await pool.query(
        `INSERT INTO staff_accounts (phone, password_hash, role, display_name)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (phone) DO UPDATE
           SET password_hash = EXCLUDED.password_hash,
               role          = EXCLUDED.role,
               display_name  = EXCLUDED.display_name`,
        [a.phone, a.passwordHash, a.role, a.displayName ?? ''],
      );
    },

    async createStaffAccount(a) {
      // DO NOTHING rather than DO UPDATE: a duplicate phone means somebody is
      // already using this number, and quietly overwriting their password would
      // lock them out of a back office they are currently signed in to.
      const { rows } = await pool.query(
        `INSERT INTO staff_accounts (phone, password_hash, role, display_name)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (phone) DO NOTHING
         RETURNING id`,
        [a.phone, a.passwordHash, a.role, a.displayName],
      );
      return rows[0] ? { id: rows[0].id } : null;
    },

    async listStaffAccounts() {
      const { rows } = await pool.query(
        `SELECT id, phone, role, display_name, disabled_at, created_at, last_login_at
           FROM staff_accounts
          ORDER BY disabled_at NULLS FIRST, created_at`,
      );
      return rows.map((r) => ({
        id: r.id,
        phone: r.phone,
        role: r.role,
        displayName: r.display_name,
        disabled: r.disabled_at !== null,
        createdAt: new Date(r.created_at).toISOString(),
        lastLoginAt: r.last_login_at ? new Date(r.last_login_at).toISOString() : null,
      }));
    },

    async updateStaffAccount(id, patch) {
      // Built rather than written out, so an absent field is left alone instead
      // of being written as null — which is how a role edit would erase a name.
      const sets: string[] = [];
      const vals: unknown[] = [];
      if (patch.role !== undefined) { vals.push(patch.role); sets.push(`role = $${vals.length}`); }
      if (patch.displayName !== undefined) { vals.push(patch.displayName); sets.push(`display_name = $${vals.length}`); }
      if (patch.passwordHash !== undefined) { vals.push(patch.passwordHash); sets.push(`password_hash = $${vals.length}`); }
      if (patch.disabled !== undefined) sets.push(`disabled_at = ${patch.disabled ? 'now()' : 'NULL'}`);
      if (sets.length === 0) return;
      vals.push(id);
      await pool.query(`UPDATE staff_accounts SET ${sets.join(', ')} WHERE id = $${vals.length}`, vals);
    },

    async deleteStaffSessionsFor(staffId) {
      const { rowCount } = await pool.query('DELETE FROM staff_sessions WHERE staff_id = $1', [staffId]);
      return rowCount ?? 0;
    },

    async touchStaffLogin(staffId) {
      await pool.query('UPDATE staff_accounts SET last_login_at = now() WHERE id = $1', [staffId]);
    },

    async createStaffSession(s) {
      await pool.query(
        `INSERT INTO staff_sessions (token_hash, staff_id, expires_at, user_agent)
         VALUES ($1,$2,$3,$4)`,
        [s.tokenHash, s.staffId, s.expiresAt, s.userAgent.slice(0, 300)],
      );
      // Sweep here rather than on a timer: this runs a few times a day, which is
      // exactly often enough, and it keeps the table from growing without a
      // background job nobody would notice had stopped.
      await pool.query('DELETE FROM staff_sessions WHERE expires_at < now()');
    },

    async staffBySessionToken(tokenHash) {
      const { rows } = await pool.query(
        `SELECT s.staff_id, a.role, a.display_name, a.phone
           FROM staff_sessions s
           JOIN staff_accounts a ON a.id = s.staff_id
          WHERE s.token_hash = $1
            AND s.expires_at > now()
            AND a.disabled_at IS NULL`,
        [tokenHash],
      );
      const r = rows[0];
      return r
        ? { staffId: r.staff_id, role: r.role, displayName: r.display_name ?? '', phone: r.phone }
        : null;
    },

    async deleteStaffSession(tokenHash) {
      await pool.query('DELETE FROM staff_sessions WHERE token_hash = $1', [tokenHash]);
    },

    async recentFailedLogins(phone, since) {
      const { rows } = await pool.query(
        `SELECT count(*)::int AS n FROM staff_login_attempts
          WHERE phone = $1 AND at >= $2 AND succeeded = false`,
        [phone, since],
      );
      return rows[0]?.n ?? 0;
    },

    async recordLoginAttempt(phone, succeeded) {
      await pool.query(
        'INSERT INTO staff_login_attempts (phone, succeeded) VALUES ($1,$2)',
        [phone, succeeded],
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
      // NO uuid guard here, unlike its neighbours: a device is keyed by its
      // physical identifier, which is a MAC or a serial and a TEXT column. The
      // guard belongs on the lookups that compare against a UUID column, and
      // putting it here would refuse every real device.
      const { rows } = await pool.query(`SELECT user_id FROM devices WHERE ble_mac = $1`, [deviceId]);
      return rows[0] ? { userId: rows[0].user_id } : null;
    },

    async childOwner(childId) {
      // A malformed id is an id we do not have, not a server fault.
      if (!looksLikeUuid(childId)) return null;
      const { rows } = await pool.query(`SELECT guardian_id FROM children WHERE id = $1`, [childId]);
      return rows[0] ? { userId: rows[0].guardian_id } : null;
    },

    async geofenceOwner(geofenceId) {
      // A malformed id is an id we do not have, not a server fault.
      if (!looksLikeUuid(geofenceId)) return null;
      const { rows } = await pool.query(`SELECT guardian_id FROM geofences WHERE id = $1`, [geofenceId]);
      return rows[0] ? { userId: rows[0].guardian_id } : null;
    },

    // ---- CRUD + history ----
    async listChildren(userId) {
      const { rows } = await pool.query(
        `SELECT id, name, gender, date_of_birth FROM children WHERE guardian_id = $1 ORDER BY created_at`, [userId]);
      return rows.map((r) => ({
        id: r.id, name: r.name, gender: r.gender ?? null,
        dateOfBirth: r.date_of_birth ? new Date(r.date_of_birth).toISOString().slice(0, 10) : null,
      }));
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
        `SELECT ble_mac, model, name, kind, child_id FROM devices WHERE user_id = $1 ORDER BY paired_at`, [userId]);
      return rows.map((r) => ({
        // ble_mac, not id: the app stores a device under its physical
        // identifier, so anything else comes back as a device it does not
        // recognise and it registers a duplicate on the next sync.
        id: r.ble_mac, name: r.name ?? r.model ?? r.ble_mac, kind: r.kind ?? 'band', childId: r.child_id ?? null,
      }));
    },
    // A device id from the app is a PHYSICAL identifier — a BLE MAC or a
    // serial, whatever is printed on the tracker — and that is what `ble_mac`
    // is for. This wrote it into `id` as well, which is a UUID column, so
    // registering a device raised 22P02 and the app got a 500: pairing a
    // tracker, the thing the hardware is sold for, could not reach the server
    // at all. The UUID is ours to mint; the MAC is hers to keep.
    async createDevice(userId, d) {
      await pool.query(
        `INSERT INTO devices (user_id, ble_mac, model, kind, name, child_id)
         VALUES ($1,$2,$3,$4,$5,$6)
         ON CONFLICT (user_id, ble_mac) DO NOTHING`,
        [userId, d.id, d.name, d.kind, d.name, d.childId ?? null]);
    },
    async deleteDevice(deviceId) {
      await pool.query(`DELETE FROM devices WHERE ble_mac = $1`, [deviceId]);
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
      // A malformed id is an id we do not have, not a server fault.
      if (!looksLikeUuid(id)) return null;
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
      // A malformed id is an id we do not have, not a server fault.
      if (!looksLikeUuid(id)) return null;
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
          `INSERT INTO geofences (id, guardian_id, child_id, name, shape, center_lat, center_lng, radius_m)
           VALUES ($6, (SELECT guardian_id FROM children WHERE id=$1), $1, $2, 'circle', $3, $4, $5)
           ON CONFLICT (id) DO UPDATE
             SET name = EXCLUDED.name, shape = EXCLUDED.shape,
                 center_lat = EXCLUDED.center_lat, center_lng = EXCLUDED.center_lng,
                 radius_m = EXCLUDED.radius_m, area_geojson = NULL`,
          [childId, g.name, g.center!.lat, g.center!.lng, g.radiusM, g.id]);
        return;
      }
      // Store a closed-ring GeoJSON Polygon ([lng,lat] pairs), the shape loadGeofences reads.
      const ring = g.vertices!.map((v) => [v.lng, v.lat]);
      ring.push([g.vertices![0].lng, g.vertices![0].lat]); // close the ring
      const areaGeojson = JSON.stringify({ type: 'Polygon', coordinates: [ring] });
      await pool.query(
        `INSERT INTO geofences (id, guardian_id, child_id, name, shape, area_geojson)
         VALUES ($4, (SELECT guardian_id FROM children WHERE id=$1), $1, $2, 'polygon', $3::jsonb)
         ON CONFLICT (id) DO UPDATE
           SET name = EXCLUDED.name, shape = EXCLUDED.shape, area_geojson = EXCLUDED.area_geojson,
               center_lat = NULL, center_lng = NULL, radius_m = NULL`,
        [childId, g.name, areaGeojson, g.id]);
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

    async upsertGrowth(childId, g) {
      await pool.query(
        `INSERT INTO child_growth (child_id, at, weight_kg, height_cm)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (child_id, at) DO UPDATE
           SET weight_kg = EXCLUDED.weight_kg, height_cm = EXCLUDED.height_cm`,
        [childId, g.at, g.weightKg, g.heightCm]);
    },
    async listGrowth(userId) {
      const { rows } = await pool.query(
        `SELECT c.id AS child_id, c.name AS child_name, g.at, g.weight_kg, g.height_cm
         FROM children c JOIN child_growth g ON g.child_id = c.id
         WHERE c.guardian_id = $1 ORDER BY g.at`, [userId]);
      return rows.map((r) => ({
        childId: r.child_id, childName: r.child_name,
        at: new Date(r.at).toISOString().slice(0, 10), // yyyy-MM-dd
        weightKg: r.weight_kg === null ? null : Number(r.weight_kg),
        heightCm: r.height_cm === null ? null : Number(r.height_cm),
      }));
    },

    async upsertDose(userId, d) {
      await pool.query(
        `INSERT INTO med_doses (med_id, user_id, log_date, count)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (med_id, log_date) DO UPDATE SET count = EXCLUDED.count`,
        [d.medId, userId, d.date, d.count]);
    },
    async listDoses(userId) {
      const { rows } = await pool.query(
        `SELECT med_id, log_date, count FROM med_doses
         WHERE user_id = $1 ORDER BY log_date DESC`, [userId]);
      return rows.map((r) => ({
        medId: r.med_id, date: new Date(r.log_date).toISOString().slice(0, 10), count: Number(r.count),
      }));
    },

    async setVaccine(childId, vaccineKey, done) {
      if (done) {
        await pool.query(
          `INSERT INTO child_vaccines (child_id, vaccine_key) VALUES ($1,$2)
           ON CONFLICT (child_id, vaccine_key) DO NOTHING`, [childId, vaccineKey]);
      } else {
        await pool.query(
          `DELETE FROM child_vaccines WHERE child_id = $1 AND vaccine_key = $2`, [childId, vaccineKey]);
      }
    },
    async listVaccines(userId) {
      const { rows } = await pool.query(
        `SELECT c.id AS child_id, c.name AS child_name, v.vaccine_key
         FROM children c JOIN child_vaccines v ON v.child_id = c.id
         WHERE c.guardian_id = $1 ORDER BY c.name, v.vaccine_key`, [userId]);
      return rows.map((r) => ({ childId: r.child_id, childName: r.child_name, vaccineKey: r.vaccine_key }));
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
    async getChildEmergency(childId) {
      const { rows } = await pool.query(
        `SELECT blood_type, allergies, conditions, medications, doctor_name, doctor_phone,
                contact_name, contact_phone, notes
         FROM child_emergency WHERE child_id = $1`, [childId]);
      const r = rows[0];
      if (!r) return null;
      return {
        bloodType: r.blood_type ?? '', allergies: r.allergies ?? '', conditions: r.conditions ?? '',
        medications: r.medications ?? '', doctorName: r.doctor_name ?? '', doctorPhone: r.doctor_phone ?? '',
        contactName: r.contact_name ?? '', contactPhone: r.contact_phone ?? '', notes: r.notes ?? '',
      };
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
        // The LATERAL pulls each user's most recent reading — its time (the
        // "last measurement" column, which returned nothing before) and its
        // triage severity (so a warning/emergency shows in the LIST, not only
        // after opening the drawer). idx_phm_user_time makes it a one-row scan.
        `SELECT u.id, u.display_name, u.phone_e164, u.due_date, m.triage_severity, m.recorded_at
         FROM users u
         LEFT JOIN LATERAL (
           SELECT triage_severity, recorded_at FROM pregnancy_health_metrics
           WHERE user_id = u.id ORDER BY recorded_at DESC LIMIT 1
         ) m ON true
         WHERE u.display_name ILIKE $1 OR u.email ILIKE $1
         ORDER BY u.created_at DESC LIMIT $2 OFFSET $3`,
        [like, limit, offset]);
      return {
        total: total.rows[0].n,
        users: rows.map((r) => ({
          id: r.id, displayName: r.display_name, phone: r.phone_e164, dueDate: r.due_date,
          lastMetricAt: r.recorded_at ? new Date(r.recorded_at).toISOString() : null,
          latestSeverity: r.triage_severity ?? null,
        })),
      };
    },
    async adminUserHealth(userId) {
      const latest = await pool.query(
        `SELECT heart_rate_bpm, spo2_pct, systolic_mmhg, diastolic_mmhg, core_temp_c, glucose_mmol
         FROM pregnancy_health_metrics WHERE user_id = $1 ORDER BY recorded_at DESC LIMIT 1`, [userId]);
      if (latest.rows.length === 0) return null;
      const r = latest.rows[0];
      const triage = await pool.query(
        `SELECT triage_severity, recorded_at FROM pregnancy_health_metrics
         WHERE user_id = $1 AND triage_severity IN ('warning','emergency') ORDER BY recorded_at DESC LIMIT 20`, [userId]);
      return {
        latest: { hr: r.heart_rate_bpm, spo2: r.spo2_pct, systolic: r.systolic_mmhg, diastolic: r.diastolic_mmhg, temp: r.core_temp_c, glucose: r.glucose_mmol },
        triage: triage.rows.map((t) => ({ code: t.triage_severity, severity: t.triage_severity, at: new Date(t.recorded_at).toISOString() })),
      };
    },
    async writeAudit(entry) {
      await pool.query(`INSERT INTO audit_log (staff_id, action, target) VALUES ($1,$2,$3)`,
        [entry.staffId, entry.action, entry.target ?? null]);
    },
    async listAudit(limit) {
      // Joined to the roster on both ends. The log's whole purpose is "who
      // looked at this mother's data", and it answered that with a UUID —
      // which nobody can read, and which the panel then printed verbatim.
      //
      // LEFT JOIN, and the id is still returned: entries written before there
      // were accounts (or by an account since removed) must stay visible.
      // Dropping them would make the log lie by omission.
      const { rows } = await pool.query(
        `SELECT l.staff_id, l.action, l.target, l.at,
                a.display_name AS staff_name, a.phone AS staff_phone,
                t.display_name AS target_name, t.phone AS target_phone
           FROM audit_log l
           LEFT JOIN staff_accounts a ON a.id::text = l.staff_id
           LEFT JOIN staff_accounts t ON t.id::text = l.target
          ORDER BY l.at DESC
          LIMIT $1`,
        [limit],
      );
      return rows.map((r) => ({
        staffId: r.staff_id,
        staffName: r.staff_name ?? null,
        staffPhone: r.staff_phone ?? null,
        action: r.action,
        target: r.target,
        targetName: r.target_name ?? null,
        at: new Date(r.at).toISOString(),
      }));
    },

    // ---- Back-office drilldowns ----
    async adminUserDetail(userId) {
      const { rows: prof } = await pool.query(
        // phone_e164 AS phone: the column is phone_e164, and the bare `phone`
        // this used would throw "column does not exist" on real Postgres —
        // the whole detail card failed against pg while passing the in-memory tests.
        `SELECT display_name, phone_e164 AS phone, due_date, locale, birth_date, city,
                doctor_phone, avg_cycle_length, avg_period_length FROM users WHERE id = $1`, [userId]);
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
        doctorPhone: prof[0].doctor_phone ?? null,
        avgCycleLength: prof[0].avg_cycle_length === null ? null : Number(prof[0].avg_cycle_length),
        avgPeriodLength: prof[0].avg_period_length === null ? null : Number(prof[0].avg_period_length),
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
        `SELECT d.ble_mac, d.name, d.kind, d.user_id, d.battery_pct, d.last_seen,
                u.display_name, c.name AS child_name
           FROM devices d
           JOIN users u ON u.id = d.user_id
           LEFT JOIN children c ON c.id = d.child_id
          ORDER BY d.last_seen DESC NULLS LAST LIMIT $1`, [limit]);
      return rows.map((r) => ({
        // The identifier printed on the hardware, not our internal UUID. This
        // table is read by somebody on a support call asking "what does it say
        // on the back of the tracker" — a UUID we invented answers nothing,
        // and it is what the row falls back to when a device has no name.
        id: r.ble_mac, name: r.name, kind: r.kind, userId: r.user_id,
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

    async dashboardSnapshot(asOf) {
      // One round trip per subject area rather than per number: the panel used
      // to stitch six endpoints together and the totals on screen were as of
      // six different instants, so "12 users, 13 cities" was reachable and
      // looked like a bug in the arithmetic.
      const [users, mothers, devices, cities, leads, orders, stock, childRows] = await Promise.all([
        pool.query(`
          SELECT count(*) AS total,
                 count(*) FILTER (WHERE created_at >= date_trunc('day', now())) AS new_today,
                 count(*) FILTER (WHERE created_at > now() - interval '7 days') AS new_7d,
                 count(*) FILTER (WHERE created_at > now() - interval '30 days') AS new_30d,
                 -- Counted here, not by subtracting the top-N city list: with
                 -- more cities than that list shows, the subtraction reports
                 -- every user beyond the 12th city as "city unknown".
                 count(*) FILTER (WHERE city IS NULL OR btrim(city) = '') AS no_city
            FROM users`),
        // Pregnant and mother deliberately overlap — see DashboardSnapshot.
        pool.query(`
          SELECT count(*) FILTER (WHERE u.due_date IS NOT NULL AND u.due_date >= current_date) AS pregnant,
                 count(*) FILTER (WHERE k.n > 0) AS mothers,
                 count(*) FILTER (WHERE u.due_date IS NOT NULL AND u.due_date >= current_date AND k.n > 0) AS both,
                 count(*) FILTER (WHERE (u.due_date IS NULL OR u.due_date < current_date) AND k.n = 0) AS unknown
            FROM users u
            LEFT JOIN LATERAL (SELECT count(*) AS n FROM children c WHERE c.guardian_id = u.id) k ON TRUE`),
        pool.query(`
          SELECT count(*) AS total,
                 count(*) FILTER (WHERE last_seen > now() - interval '24 hours') AS online,
                 count(*) FILTER (WHERE kind = 'band') AS watches,
                 count(*) FILTER (WHERE kind = 'tag') AS trackers,
                 count(*) FILTER (WHERE kind = 'tag' AND child_id IS NULL) AS unassigned
            FROM devices`),
        // Trimmed and case-folded: "Алматы", "алматы " and "Алматы" are one
        // city, and three rows of the same place is not a distribution.
        pool.query(`
          SELECT initcap(btrim(city)) AS city, count(*)::int AS users
            FROM users
           WHERE city IS NOT NULL AND btrim(city) <> ''
           GROUP BY initcap(btrim(city))
           ORDER BY users DESC, city ASC
           LIMIT 12`),
        pool.query(`
          SELECT count(*) AS total, count(*) FILTER (WHERE status = 'new') AS fresh
            FROM shop_leads`),
        pool.query(`
          SELECT count(*) AS total,
                 count(*) FILTER (WHERE status = 'new') AS s_new,
                 count(*) FILTER (WHERE status = 'confirmed') AS s_confirmed,
                 count(*) FILTER (WHERE status = 'shipped') AS s_shipped,
                 count(*) FILTER (WHERE status = 'delivered') AS s_delivered,
                 count(*) FILTER (WHERE status = 'cancelled') AS s_cancelled,
                 -- Earned means it left the building. A 'new' order is a phone
                 -- call, and counting it as revenue overstates the month.
                 COALESCE(sum(total_minor) FILTER (WHERE status IN ('shipped','delivered')), 0) AS revenue,
                 COALESCE(sum(total_minor) FILTER (WHERE status IN ('new','confirmed')), 0) AS pipeline
            FROM shop_orders`),
        // Bundles hold no stock of their own, so counting them would count
        // their parts twice.
        pool.query(`
          SELECT COALESCE(sum(v.stock), 0)::int AS units,
                 COALESCE(sum(v.stock * p.price_minor), 0)::bigint AS retail,
                 COALESCE(sum(v.stock * p.cost_minor) FILTER (WHERE p.cost_minor IS NOT NULL), 0)::bigint AS cost,
                 COALESCE(sum(v.stock) FILTER (WHERE p.cost_minor IS NULL), 0)::int AS units_no_cost
            FROM shop_variants v
            JOIN shop_products p ON p.id = v.product_id
           WHERE COALESCE(p.kind, 'simple') <> 'bundle'`),
        pool.query(`SELECT gender, date_of_birth FROM children`),
      ]);

      const u = users.rows[0] ?? {}, m = mothers.rows[0] ?? {}, d = devices.rows[0] ?? {};
      const l = leads.rows[0] ?? {}, o = orders.rows[0] ?? {}, s = stock.rows[0] ?? {};
      const n = (v: unknown) => Number(v ?? 0);

      // DAU/WAU/MAU and retention come from the same definitions the Аналитика
      // tab uses — two dashboards disagreeing about "active" is worse than one
      // extra query.
      const bi = await this.adminBiMetrics();
      const shipped = n(o.s_shipped) + n(o.s_delivered);

      // Which products are at or below their threshold. adminProducts already
      // derives bundle stock from parts and flags low stock one way.
      const lowStock = (await this.adminProducts()).filter((p) => p.lowStock).map((p) => p.id);

      // The course. One query, because the interesting number is a comparison:
      // how many were given it against how many have ever pressed play.
      //
      // "Finished" is measured against the count of published lessons, so
      // publishing a new lesson correctly moves people out of finished — they
      // have not watched it yet. Nobody is finished while there is nothing to
      // finish, which is why the count is guarded rather than defaulting to 0.
      const { rows: cr } = await pool.query(
        `WITH pub AS (
           SELECT COUNT(*)::int AS n FROM course_lessons
            WHERE course = 'mama' AND published = TRUE
         ), per AS (
           SELECT p.phone,
                  COUNT(*) FILTER (WHERE l.published)::int                    AS started,
                  COUNT(*) FILTER (WHERE l.published AND p.completed)::int    AS done,
                  MAX(p.updated_at)                                           AS last_at
             FROM course_progress p
             JOIN course_lessons l ON l.id = p.lesson_id
            GROUP BY p.phone
         )
         SELECT (SELECT n FROM pub)                                            AS lessons,
                (SELECT COUNT(*)::int FROM user_entitlements
                  WHERE feature = 'mama_course')                               AS granted,
                (SELECT COUNT(*)::int FROM per WHERE started > 0)              AS started,
                (SELECT COUNT(*)::int FROM per
                  WHERE (SELECT n FROM pub) > 0 AND done >= (SELECT n FROM pub)) AS finished,
                (SELECT COALESCE(SUM(done), 0)::int FROM per)                   AS lessons_completed,
                (SELECT COUNT(*)::int FROM per
                  WHERE last_at >= $1::timestamptz - INTERVAL '7 days')         AS active_7d`,
        [asOf]);
      const c = cr[0] ?? {};

      return {
        asOf,
        users: {
          total: n(u.total), newToday: n(u.new_today), new7d: n(u.new_7d), new30d: n(u.new_30d),
          dau: bi.dau, wau: bi.wau, mau: bi.mau,
          retentionD7: bi.retention.d7.cohort > 0 ? bi.retention.d7.rate : null,
        },
        mothers: {
          pregnant: n(m.pregnant), mothers: n(m.mothers), both: n(m.both), unknown: n(m.unknown),
        },
        children: computeChildrenStats(
          childRows.rows.map((r) => ({
            gender: r.gender as string | null,
            dateOfBirth: r.date_of_birth ? new Date(r.date_of_birth as string).toISOString().slice(0, 10) : null,
          })),
          asOf,
        ),
        devices: {
          total: n(d.total), online: n(d.online), watches: n(d.watches),
          trackers: n(d.trackers), unassigned: n(d.unassigned),
        },
        cities: cities.rows.map((r) => ({ city: String(r.city), users: n(r.users) })),
        citiesUnknown: n(u.no_city),
        commerce: {
          leads: { total: n(l.total), new: n(l.fresh) },
          orders: {
            total: n(o.total), new: n(o.s_new), confirmed: n(o.s_confirmed),
            shipped: n(o.s_shipped), delivered: n(o.s_delivered), cancelled: n(o.s_cancelled),
          },
          revenueMinor: n(o.revenue),
          pipelineMinor: n(o.pipeline),
          avgOrderMinor: shipped > 0 ? Math.round(n(o.revenue) / shipped) : null,
          stock: {
            units: n(s.units), retailMinor: n(s.retail), costMinor: n(s.cost),
            unitsWithoutCost: n(s.units_no_cost),
          },
          lowStock,
        },
        course: {
          lessons: n(c.lessons), granted: n(c.granted), started: n(c.started),
          finished: n(c.finished), lessonsCompleted: n(c.lessons_completed),
          active7d: n(c.active_7d),
        },
      };
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

      // Where the users actually are, in the CMS's own stage keys.
      //
      // This field was declared, documented and hardcoded to `{}` in both
      // repositories, so nothing ever had a value to draw. It is the other half
      // of the content counts beside it: knowing 47 stages have material is
      // only useful next to which stages people are standing in. Otherwise the
      // authoring backlog is ordered by guesswork.
      //
      // An account can appear in more than one stage, exactly as the pregnant /
      // mothers counts already overlap — a mother expecting her second reads
      // her week AND her toddler's month, and forcing her into one would
      // misstate whichever number somebody happens to read.
      const { rows: stageRows } = await pool.query(
        `WITH preg AS (
           SELECT DISTINCT id AS uid,
                  'w' || GREATEST(1, LEAST(40, 40 - ((due_date - CURRENT_DATE) / 7))) AS stage
             FROM users
            WHERE due_date IS NOT NULL
              -- A due date in the past is not week 41; it is a birth nobody
              -- recorded. Counting it would pile every stale account onto w40.
              AND due_date >= CURRENT_DATE
         ), kids AS (
           SELECT DISTINCT guardian_id AS uid,
                  'm' || LEAST(60, GREATEST(0,
                    (EXTRACT(YEAR FROM age(CURRENT_DATE, date_of_birth)) * 12
                     + EXTRACT(MONTH FROM age(CURRENT_DATE, date_of_birth)))::int)) AS stage
             FROM children
            WHERE date_of_birth IS NOT NULL AND guardian_id IS NOT NULL
              AND date_of_birth <= CURRENT_DATE
         )
         SELECT stage, COUNT(*)::int AS n
           FROM (SELECT * FROM preg UNION ALL SELECT * FROM kids) both
          GROUP BY stage`);
      const stageDistribution: Record<string, number> = {};
      for (const s of stageRows) stageDistribution[String(s.stage)] = Number(s.n);

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
        stageDistribution,
        contentStages: Object.keys(catalog).length,
        contentStageKeys: Object.keys(catalog).filter((k) => catalog[k].length > 0),
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
        `INSERT INTO sleep_nights (user_id, night, deep_min, rem_min, light_min, awake_min, source, manual_asleep_min)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         ON CONFLICT (user_id, night) DO UPDATE
           SET deep_min = EXCLUDED.deep_min, rem_min = EXCLUDED.rem_min,
               light_min = EXCLUDED.light_min, awake_min = EXCLUDED.awake_min,
               source = EXCLUDED.source, manual_asleep_min = EXCLUDED.manual_asleep_min`,
        [userId, s.night, s.deepMin, s.remMin, s.lightMin, s.awakeMin, s.source ?? null, s.manualAsleepMin ?? null]);
    },
    async listSleep(userId, limit) {
      const { rows } = await pool.query(
        `SELECT night, deep_min, rem_min, light_min, awake_min, source, manual_asleep_min FROM sleep_nights
         WHERE user_id = $1 ORDER BY night DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({
        night: new Date(r.night).toISOString(),
        deepMin: r.deep_min, remMin: r.rem_min, lightMin: r.light_min, awakeMin: r.awake_min,
        source: r.source ?? undefined,
        manualAsleepMin: r.manual_asleep_min ?? null,
      }));
    },

    // ---- Baby cry-analysis history ----
    async recordCry(userId, c) {
      await pool.query(
        `INSERT INTO cry_results (user_id, at, reason, confidence)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (user_id, at) DO UPDATE
           SET reason = EXCLUDED.reason, confidence = EXCLUDED.confidence`,
        [userId, c.at, c.reason, c.confidence]);
    },
    async listCry(userId, limit) {
      const { rows } = await pool.query(
        `SELECT at, reason, confidence FROM cry_results
         WHERE user_id = $1 ORDER BY at DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({
        at: new Date(r.at).toISOString(), reason: r.reason, confidence: Number(r.confidence),
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
        `INSERT INTO cycle_day_logs (user_id, log_date, mood, symptoms, kicks, flow, note)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT (user_id, log_date) DO UPDATE
           SET mood = EXCLUDED.mood, symptoms = EXCLUDED.symptoms,
               kicks = EXCLUDED.kicks, flow = EXCLUDED.flow, note = EXCLUDED.note`,
        [userId, log.date, log.mood, log.symptoms, log.kicks, log.flow, log.note ?? null]);
    },
    async listDayLogs(userId, from, to) {
      const { rows } = await pool.query(
        `SELECT log_date, mood, symptoms, kicks, flow, note FROM cycle_day_logs
         WHERE user_id = $1 AND log_date BETWEEN $2 AND $3 ORDER BY log_date`, [userId, from, to]);
      return rows.map((r) => ({
        date: r.log_date, mood: r.mood, symptoms: r.symptoms ?? [], kicks: r.kicks, flow: r.flow,
        note: r.note ?? '',
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
        `SELECT display_name, phone_e164, due_date, locale, birth_date, city,
                doctor_phone, avg_cycle_length, avg_period_length
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
        doctorPhone: r.doctor_phone ?? null,
        avgCycleLength: r.avg_cycle_length === null ? null : Number(r.avg_cycle_length),
        avgPeriodLength: r.avg_period_length === null ? null : Number(r.avg_period_length),
      };
    },
    async upsertProfile(userId, p) {
      // The user row exists from signup (email is required); this updates it.
      await pool.query(
        `UPDATE users SET display_name = $2, phone_e164 = $3, due_date = $4,
                          locale = COALESCE($5, locale),
                          birth_date = $6, city = $7, doctor_phone = $8,
                          avg_cycle_length = $9, avg_period_length = $10, updated_at = now()
         WHERE id = $1`,
        [userId, p.displayName, p.phone, p.dueDate, p.locale, p.birthDate, p.city,
         p.doctorPhone, p.avgCycleLength, p.avgPeriodLength]);
    },

    // ---- Device reassignment ----
    async reassignDevice(deviceId, childId) {
      await pool.query(`UPDATE devices SET child_id = $2 WHERE ble_mac = $1`, [deviceId, childId]);
    },

    // ---- Shop ----
    async shopProducts() {
      const { rows } = await pool.query(
        `SELECT p.id, p.name, p.price_minor, COALESCE(p.kind, 'simple') AS kind,
                v.id AS vid, v.color, v.color_hex, v.stock
         FROM shop_products p
         LEFT JOIN shop_variants v ON v.product_id = p.id
         WHERE p.active = TRUE
         ORDER BY p.sort, v.sort, v.color`,
      );
      const { rows: partRows } = await pool.query(
        'SELECT bundle_id, part_id, qty FROM shop_bundle_items');
      const byId = new Map<string, ShopProduct>();
      for (const r of rows) {
        let p = byId.get(r.id);
        if (!p) {
          p = { id: r.id, name: r.name, priceMinor: r.price_minor, variants: [], kind: r.kind, parts: [] };
          byId.set(r.id, p);
        }
        if (r.vid) p.variants.push({ id: r.vid, color: r.color, colorHex: r.color_hex, stock: r.stock });
      }
      for (const r of partRows) byId.get(r.bundle_id)?.parts.push({ partId: r.part_id, qty: r.qty });
      return [...byId.values()];
    },

    async placeShopOrder(o) {
      if (!o.items.length) return { ok: false, error: 'empty' };
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        let subtotal = 0;
        const lines: Array<{ productId: string; qty: number }> = [];
        const snap: Array<{ variantId: string; productName: string; color: string; qty: number; unit: number }> = [];
        for (const it of o.items) {
          // FOR UPDATE locks the row for the transaction — two buyers racing for
          // the last unit serialise here instead of both succeeding.
          const { rows } = await client.query(
            `SELECT v.id, v.color, v.stock, v.product_id, p.name, p.price_minor
             FROM shop_variants v JOIN shop_products p ON p.id = v.product_id
             WHERE v.id = $1 FOR UPDATE`, [it.variantId]);
          if (!rows.length) { await client.query('ROLLBACK'); return { ok: false, error: 'not_found', variantId: it.variantId }; }
          const v = rows[0];
          if (v.stock < it.qty) { await client.query('ROLLBACK'); return { ok: false, error: 'out_of_stock', variantId: it.variantId }; }
          await client.query('UPDATE shop_variants SET stock = stock - $2 WHERE id = $1', [it.variantId, it.qty]);
          subtotal += v.price_minor * it.qty;
          lines.push({ productId: v.product_id, qty: it.qty });
          snap.push({ variantId: v.id, productName: v.name, color: v.color, qty: it.qty, unit: v.price_minor });
        }
        let discount = bundleDiscountMinor(lines);
        let total = subtotal - discount;

        // Sold as a bundle: the parts are what left the warehouse, but the
        // PRICE is the bundle's. The parts must actually be the bundle's parts
        // — otherwise "sold as the combo" could be claimed over one tracker and
        // buy the course for 4 900.
        if (o.bundleId) {
          const { rows: bundle } = await client.query(
            'SELECT price_minor FROM shop_products WHERE id = $1 AND kind = $2',
            [o.bundleId, 'bundle']);
          if (!bundle.length) { await client.query('ROLLBACK'); return { ok: false, error: 'not_found', variantId: o.bundleId }; }

          const { rows: parts } = await client.query(
            'SELECT part_id, qty FROM shop_bundle_items WHERE bundle_id = $1', [o.bundleId]);
          const ordered = new Map<string, number>();
          for (const l of lines) ordered.set(l.productId, (ordered.get(l.productId) ?? 0) + l.qty);
          const complete = parts.length > 0
            && parts.every((p) => (ordered.get(p.part_id) ?? 0) >= p.qty);
          if (!complete) { await client.query('ROLLBACK'); return { ok: false, error: 'incomplete_bundle', variantId: o.bundleId }; }

          total = bundle[0].price_minor;
          // Recorded as a discount only when it IS one. The комплект costs MORE
          // than its parts because it carries the course, so this is normally
          // zero rather than a negative "discount" nobody could read.
          discount = Math.max(0, subtotal - total);
        }

        const { rows: orows } = await client.query(
          `INSERT INTO shop_orders (customer_name, phone, city, address, note,
                                    total_minor, discount_minor, bundle_id, phone_normalized)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
          [o.customerName, o.phone, o.city, o.address, o.note ?? null, total, discount,
           o.bundleId ?? null, normalizePhone(o.phone)]);
        const orderId = orows[0].id as string;
        for (const s of snap) {
          await client.query(
            `INSERT INTO shop_order_items (order_id, variant_id, product_name, color, qty, unit_price_minor)
             VALUES ($1,$2,$3,$4,$5,$6)`,
            [orderId, s.variantId, s.productName, s.color, s.qty, s.unit]);
          // The sale goes in the ledger, inside the same transaction that took
          // the stock. Written here rather than through moveStock() because the
          // decrement above already happened under this transaction's lock —
          // calling out would take a second lock and could deadlock against
          // another order holding them in the other order.
          //
          // Without this, sales were the one kind of stock movement that left
          // no trace: the count fell and the ledger said nothing, so the two
          // disagreed by exactly everything ever sold.
          await client.query(
            `INSERT INTO shop_stock_moves (variant_id, delta, reason, order_id)
             VALUES ($1,$2,'sale',$3)`,
            [s.variantId, -s.qty, orderId]);
        }
        await client.query('COMMIT');
        return { ok: true, id: orderId, totalMinor: total, discountMinor: discount };
      } catch (e) {
        await client.query('ROLLBACK').catch(() => {});
        throw e;
      } finally {
        client.release();
      }
    },

    async adminShopVariants() {
      const { rows } = await pool.query(
        `SELECT v.id, v.color, v.color_hex, v.stock, v.product_id, p.name AS product_name
         FROM shop_variants v JOIN shop_products p ON p.id = v.product_id
         ORDER BY p.sort, v.sort, v.color`);
      return rows.map((r) => ({ id: r.id, color: r.color, colorHex: r.color_hex, stock: r.stock, productId: r.product_id, productName: r.product_name }));
    },
    async setShopVariantStock(variantId, stock, by) {
      // An absolute count, because a stocktake knows the total rather than the
      // difference. The ledger still gets the delta, so the running total and
      // the history cannot drift apart — which they would if this wrote the
      // column directly, as it used to.
      const target = Math.max(0, Math.trunc(stock));
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const { rows } = await client.query(
          'SELECT stock FROM shop_variants WHERE id = $1 FOR UPDATE', [variantId]);
        if (!rows[0]) { await client.query('ROLLBACK'); return; }
        const delta = target - rows[0].stock;
        if (delta !== 0) {
          await client.query('UPDATE shop_variants SET stock = $2 WHERE id = $1', [variantId, target]);
          await client.query(
            `INSERT INTO shop_stock_moves (variant_id, delta, reason, note, staff_id)
             VALUES ($1,$2,'correction',$3,$4)`,
            [variantId, delta, by?.note ?? null, by?.staffId ?? null]);
        }
        await client.query('COMMIT');
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },

    // ---- The Ма!Ма! course ----
    async courseLessons(course, publishedOnly) {
      const { rows } = await pool.query(
        `SELECT id, course, title_ru, title_kk, youtube_url, summary_ru, summary_kk,
                sort, published, created_at
           FROM course_lessons
          WHERE course = $1 ${publishedOnly ? 'AND published = TRUE' : ''}
          ORDER BY sort, created_at`,
        [course]);
      return rows.map((r) => ({
        id: r.id, course: r.course, titleRu: r.title_ru, titleKk: r.title_kk,
        youtubeUrl: r.youtube_url, summaryRu: r.summary_ru, summaryKk: r.summary_kk,
        sort: r.sort, published: r.published,
        createdAt: new Date(r.created_at).toISOString(),
      }));
    },

    async upsertCourseLesson(l) {
      if (l.id) {
        const { rows } = await pool.query(
          `UPDATE course_lessons
              SET title_ru = $2, title_kk = $3, youtube_url = $4,
                  summary_ru = $5, summary_kk = $6, sort = $7, published = $8,
                  updated_at = now()
            WHERE id = $1 RETURNING id`,
          [l.id, l.titleRu, l.titleKk ?? null, l.youtubeUrl, l.summaryRu ?? null,
           l.summaryKk ?? null, l.sort ?? 0, l.published ?? false]);
        if (rows[0]) return { id: rows[0].id };
        // Falls through to an insert: editing something that no longer exists
        // becomes a create rather than silently doing nothing.
      }
      const { rows } = await pool.query(
        `INSERT INTO course_lessons (course, title_ru, title_kk, youtube_url,
                                     summary_ru, summary_kk, sort, published)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
        [l.course, l.titleRu, l.titleKk ?? null, l.youtubeUrl, l.summaryRu ?? null,
         l.summaryKk ?? null, l.sort ?? 0, l.published ?? false]);
      return { id: rows[0].id };
    },

    async deleteCourseLesson(id) {
      await pool.query('DELETE FROM course_lessons WHERE id = $1', [id]);
    },

    async courseProgress(phone) {
      const { rows } = await pool.query(
        `SELECT lesson_id, position_seconds, duration_seconds, completed, updated_at
           FROM course_progress WHERE phone = $1`,
        [phone]);
      return rows.map((r) => ({
        lessonId: r.lesson_id,
        positionSeconds: r.position_seconds,
        durationSeconds: r.duration_seconds,
        completed: r.completed,
        updatedAt: new Date(r.updated_at).toISOString(),
      }));
    },

    async saveCourseProgress(p) {
      // A lesson id that is not a UUID would raise 22P02 rather than simply not
      // matching, turning a stale id in an old app into a 500.
      if (!looksLikeUuid(p.lessonId)) return;
      await pool.query(
        `INSERT INTO course_progress
           (phone, lesson_id, position_seconds, duration_seconds, completed)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (phone, lesson_id) DO UPDATE SET
           -- GREATEST, not the new value: the player reports 0 while it is still
           -- loading, and a stray beat of that would throw away where she was.
           position_seconds = GREATEST(course_progress.position_seconds, EXCLUDED.position_seconds),
           duration_seconds = COALESCE(EXCLUDED.duration_seconds, course_progress.duration_seconds),
           -- OR, not assignment: watched is a fact about the past.
           completed        = course_progress.completed OR EXCLUDED.completed,
           updated_at       = now()`,
        [p.phone, p.lessonId, Math.max(0, Math.round(p.positionSeconds)),
         p.durationSeconds == null ? null : Math.max(0, Math.round(p.durationSeconds)),
         p.completed ?? false]);
    },

    async courseProgressSummary(limit) {
      // DISTINCT ON gives the most recent lesson per phone in the same pass as
      // the counts, rather than a second query per person.
      const { rows } = await pool.query(
        `WITH agg AS (
           SELECT phone,
                  COUNT(*)::int                                  AS started,
                  COUNT(*) FILTER (WHERE completed)::int         AS completed,
                  MAX(updated_at)                                AS last_at
             FROM course_progress GROUP BY phone
         ), last AS (
           SELECT DISTINCT ON (p.phone) p.phone, p.lesson_id, l.title_ru
             FROM course_progress p
             LEFT JOIN course_lessons l ON l.id = p.lesson_id
            ORDER BY p.phone, p.updated_at DESC
         )
         SELECT agg.phone, agg.started, agg.completed, agg.last_at,
                last.lesson_id, last.title_ru
           FROM agg LEFT JOIN last ON last.phone = agg.phone
          ORDER BY agg.last_at DESC LIMIT $1`,
        [limit]);
      return rows.map((r) => ({
        phone: r.phone,
        started: r.started,
        completed: r.completed,
        lastLessonId: r.lesson_id ?? null,
        lastLessonTitle: r.title_ru ?? null,
        lastAt: new Date(r.last_at).toISOString(),
      }));
    },

    // ---- Entitlements ----
    async hasEntitlement(phone, feature) {
      const { rows } = await pool.query(
        'SELECT 1 FROM user_entitlements WHERE phone = $1 AND feature = $2', [phone, feature]);
      return rows.length > 0;
    },

    async grantEntitlement(e) {
      // Idempotent: granting twice is the same as granting once, and the second
      // attempt keeps the first grant's provenance rather than overwriting who
      // gave it and why.
      await pool.query(
        `INSERT INTO user_entitlements (phone, feature, order_id, granted_by, note)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (phone, feature) DO NOTHING`,
        [e.phone, e.feature, e.orderId ?? null, e.grantedBy ?? null, e.note ?? null]);
    },

    async revokeEntitlement(phone, feature) {
      await pool.query(
        'DELETE FROM user_entitlements WHERE phone = $1 AND feature = $2', [phone, feature]);
    },

    async listEntitlements(feature, limit) {
      const { rows } = await pool.query(
        `SELECT phone, feature, order_id, granted_by, note, at
           FROM user_entitlements WHERE feature = $1 ORDER BY at DESC LIMIT $2`,
        [feature, limit]);
      return rows.map((r) => ({
        phone: r.phone, feature: r.feature, orderId: r.order_id,
        grantedBy: r.granted_by, note: r.note, at: new Date(r.at).toISOString(),
      }));
    },

    // ---- Inventory ----
    async adminProducts() {
      const { rows } = await pool.query(
        `SELECT p.id, p.name, p.sku, p.price_minor, p.cost_minor, p.kind, p.active,
                p.sort, p.low_stock_threshold,
                v.id AS vid, v.color, v.color_hex, v.stock
           FROM shop_products p
           LEFT JOIN shop_variants v ON v.product_id = p.id
          ORDER BY p.sort, p.name, v.sort, v.color`);

      const byId = new Map<string, InventoryProduct>();
      for (const r of rows) {
        let p = byId.get(r.id);
        if (!p) {
          p = {
            id: r.id, name: r.name, sku: r.sku, priceMinor: r.price_minor,
            costMinor: r.cost_minor, kind: r.kind, active: r.active, sort: r.sort,
            lowStockThreshold: r.low_stock_threshold,
            stock: 0, lowStock: false, variants: [],
          };
          byId.set(r.id, p);
        }
        if (r.vid) p.variants.push({ id: r.vid, color: r.color, colorHex: r.color_hex, stock: r.stock });
      }

      const products = [...byId.values()];
      for (const p of products) p.stock = p.variants.reduce((n, v) => n + v.stock, 0);

      // A bundle holds no stock of its own: it can be assembled as many times
      // as its scarcest part allows. Computed here rather than stored, so it
      // cannot disagree with the parts it is made of.
      const { rows: parts } = await pool.query(
        'SELECT bundle_id, part_id, qty FROM shop_bundle_items');
      const stockOf = new Map(products.map((p) => [p.id, p.stock]));
      for (const p of products) {
        if (p.kind !== 'bundle') continue;
        const mine = parts.filter((b) => b.bundle_id === p.id);
        p.stock = mine.length === 0
          ? 0
          : Math.min(...mine.map((b) => Math.floor((stockOf.get(b.part_id) ?? 0) / b.qty)));
      }
      for (const p of products) p.lowStock = p.active && p.stock <= p.lowStockThreshold;
      return products;
    },

    async upsertProduct(p) {
      await pool.query(
        `INSERT INTO shop_products (id, name, price_minor, cost_minor, sku, kind,
                                    low_stock_threshold, active, sort)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (id) DO UPDATE SET
           name = EXCLUDED.name,
           price_minor = EXCLUDED.price_minor,
           cost_minor = EXCLUDED.cost_minor,
           sku = EXCLUDED.sku,
           kind = EXCLUDED.kind,
           low_stock_threshold = EXCLUDED.low_stock_threshold,
           active = EXCLUDED.active,
           sort = EXCLUDED.sort`,
        [p.id, p.name, Math.max(0, Math.trunc(p.priceMinor)),
         p.costMinor == null ? null : Math.max(0, Math.trunc(p.costMinor)),
         p.sku ?? null, p.kind ?? 'simple',
         p.lowStockThreshold ?? 3, p.active ?? true, p.sort ?? 0]);
    },

    async bundleParts(bundleId) {
      const { rows } = await pool.query(
        `SELECT b.part_id, b.qty, p.name
           FROM shop_bundle_items b JOIN shop_products p ON p.id = b.part_id
          WHERE b.bundle_id = $1
          ORDER BY p.sort, p.name`, [bundleId]);
      return rows.map((r) => ({ partId: r.part_id, partName: r.name, qty: r.qty }));
    },

    async setBundleParts(bundleId, parts) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query('DELETE FROM shop_bundle_items WHERE bundle_id = $1', [bundleId]);
        for (const part of parts) {
          // A bundle containing itself makes its stock unanswerable, and the
          // CHECK in the migration refuses it — this skips rather than throws so
          // one bad row cannot lose the rest of an otherwise valid edit.
          if (part.partId === bundleId) continue;
          await client.query(
            'INSERT INTO shop_bundle_items (bundle_id, part_id, qty) VALUES ($1,$2,$3)',
            [bundleId, part.partId, Math.max(1, Math.trunc(part.qty))]);
        }
        await client.query('COMMIT');
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },

    async moveStock(m) {
      const delta = Math.trunc(m.delta);
      if (delta === 0) return { ok: false as const, error: 'insufficient_stock' as const };
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        // Locked, so two people receiving the same delivery at once cannot both
        // read the old total and write the same new one.
        const { rows } = await client.query(
          'SELECT stock FROM shop_variants WHERE id = $1 FOR UPDATE', [m.variantId]);
        if (!rows[0]) {
          await client.query('ROLLBACK');
          return { ok: false as const, error: 'unknown_variant' as const };
        }
        const next = rows[0].stock + delta;
        if (next < 0) {
          // The ledger must never describe an impossible state. Refusing is the
          // whole reason this is a transaction.
          await client.query('ROLLBACK');
          return { ok: false as const, error: 'insufficient_stock' as const };
        }
        await client.query('UPDATE shop_variants SET stock = $2 WHERE id = $1', [m.variantId, next]);
        await client.query(
          `INSERT INTO shop_stock_moves (variant_id, delta, reason, note, staff_id, order_id)
           VALUES ($1,$2,$3,$4,$5,$6)`,
          [m.variantId, delta, m.reason, m.note ?? null, m.staffId ?? null, m.orderId ?? null]);
        await client.query('COMMIT');
        return { ok: true as const, stock: next };
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },

    async stockMoves(limit, variantId) {
      const { rows } = await pool.query(
        `SELECT m.id, m.variant_id, m.delta, m.reason, m.note, m.staff_id, m.order_id, m.at,
                v.color, p.name AS product_name
           FROM shop_stock_moves m
           JOIN shop_variants v ON v.id = m.variant_id
           JOIN shop_products p ON p.id = v.product_id
          ${variantId ? 'WHERE m.variant_id = $2' : ''}
          ORDER BY m.at DESC, m.id DESC
          LIMIT $1`,
        variantId ? [limit, variantId] : [limit]);
      return rows.map((r) => ({
        id: Number(r.id), variantId: r.variant_id, productName: r.product_name,
        color: r.color, delta: r.delta, reason: r.reason, note: r.note,
        staffId: r.staff_id, orderId: r.order_id,
        at: new Date(r.at).toISOString(),
      }));
    },
    async addShopVariant(productId, color, colorHex, stock) {
      await pool.query(
        `INSERT INTO shop_variants (product_id, color, color_hex, stock)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (product_id, color) DO UPDATE SET color_hex = EXCLUDED.color_hex, stock = EXCLUDED.stock`,
        [productId, color, colorHex, Math.max(0, Math.trunc(stock))]);
    },
    async adminShopOrders(limit) {
      const { rows } = await pool.query(
        `SELECT id, customer_name, phone, city, address, note, total_minor, discount_minor, status, created_at
         FROM shop_orders ORDER BY created_at DESC LIMIT $1`, [limit]);
      if (!rows.length) return [];
      const ids = rows.map((r) => r.id);
      const { rows: items } = await pool.query(
        `SELECT order_id, product_name, color, qty, unit_price_minor
         FROM shop_order_items WHERE order_id = ANY($1)`, [ids]);
      const byOrder = new Map<string, Array<{ productName: string; color: string; qty: number; unitPriceMinor: number }>>();
      for (const it of items) {
        const arr = byOrder.get(it.order_id) ?? [];
        arr.push({ productName: it.product_name, color: it.color, qty: it.qty, unitPriceMinor: it.unit_price_minor });
        byOrder.set(it.order_id, arr);
      }
      return rows.map((r) => ({
        id: r.id, customerName: r.customer_name, phone: r.phone, city: r.city, address: r.address,
        note: r.note, totalMinor: r.total_minor, discountMinor: r.discount_minor, status: r.status,
        createdAt: new Date(r.created_at).toISOString(), items: byOrder.get(r.id) ?? [],
      }));
    },
    async setShopOrderStatus(orderId, status) {
      // Cancelling puts the goods back on the shelf.
      //
      // It did not, before: the order was marked cancelled and the stock stayed
      // gone, so every cancellation quietly shrank the sellable inventory until
      // somebody noticed the shop was "out" of something sitting in the room.
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const { rows: prev } = await client.query(
          'SELECT status FROM shop_orders WHERE id = $1 FOR UPDATE', [orderId]);
        if (!prev[0]) { await client.query('ROLLBACK'); return; }
        const was = prev[0].status as string;
        await client.query('UPDATE shop_orders SET status = $2 WHERE id = $1', [orderId, status]);

        // Fulfilling a bundle grants what the bundle promises.
        //
        // On shipped/delivered, not on 'new': these are cash on delivery, and a
        // 'new' order is a promise that may never be collected. Unlocking a
        // 40 000 ₸ course on the strength of one would be giving it away.
        if ((status === 'shipped' || status === 'delivered') && was !== 'shipped' && was !== 'delivered') {
          const { rows } = await client.query(
            `SELECT o.phone_normalized, p.grants_feature
               FROM shop_orders o
               JOIN shop_products p ON p.id = o.bundle_id
              WHERE o.id = $1 AND p.grants_feature IS NOT NULL`, [orderId]);
          const row = rows[0];
          if (row?.phone_normalized) {
            await client.query(
              `INSERT INTO user_entitlements (phone, feature, order_id, note)
               VALUES ($1,$2,$3,'выдано автоматически при отправке заказа')
               ON CONFLICT (phone, feature) DO NOTHING`,
              [row.phone_normalized, row.grants_feature, orderId]);
          }
        }

        // Only on the transition INTO cancelled, and only once: setting an
        // already-cancelled order to cancelled again must not return the stock
        // twice.
        if (status === 'cancelled' && was !== 'cancelled') {
          const { rows: items } = await client.query(
            'SELECT variant_id, qty FROM shop_order_items WHERE order_id = $1', [orderId]);
          for (const it of items) {
            await client.query(
              'UPDATE shop_variants SET stock = stock + $2 WHERE id = $1', [it.variant_id, it.qty]);
            await client.query(
              `INSERT INTO shop_stock_moves (variant_id, delta, reason, note, order_id)
               VALUES ($1,$2,'return','заказ отменён',$3)`,
              [it.variant_id, it.qty, orderId]);
          }
        }
        await client.query('COMMIT');
      } catch (e) {
        await client.query('ROLLBACK').catch(() => {});
        throw e;
      } finally {
        client.release();
      }
    },

    async recordShopLead(lead) {
      const { rows } = await pool.query(
        `INSERT INTO shop_leads (customer_name, phone, package, locale)
         VALUES ($1,$2,$3,$4) RETURNING id`,
        [lead.customerName, lead.phone, lead.package ?? '', lead.locale ?? 'ru']);
      return { id: rows[0].id as string };
    },
    async adminShopLeads(limit) {
      const { rows } = await pool.query(
        `SELECT id, customer_name, phone, package, locale, status, created_at
         FROM shop_leads ORDER BY created_at DESC LIMIT $1`, [limit]);
      return rows.map((r) => ({
        id: r.id, customerName: r.customer_name, phone: r.phone, package: r.package,
        locale: r.locale, status: r.status, createdAt: new Date(r.created_at).toISOString(),
      }));
    },
    async setShopLeadStatus(leadId, status) {
      await pool.query('UPDATE shop_leads SET status = $2 WHERE id = $1', [leadId, status]);
    },

    async getShopSettings() {
      const { rows } = await pool.query('SELECT key, value FROM shop_settings');
      return Object.fromEntries(rows.map((r) => [r.key as string, (r.value as string) ?? '']));
    },
    async setShopSettings(patch) {
      const entries = Object.entries(patch);
      if (!entries.length) return;
      for (const [key, value] of entries) {
        await pool.query(
          `INSERT INTO shop_settings (key, value, updated_at) VALUES ($1, $2, now())
           ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
          [key, value ?? ''],
        );
      }
    },

    async listDailyAudio(track) {
      const { rows } = await pool.query(
        `SELECT track, day, locale, title, mime, octet_length(bytes) AS size, updated_at
         FROM daily_audio WHERE track = $1 ORDER BY day, locale`, [track]);
      return rows.map((r) => ({
        track: r.track, day: r.day, locale: r.locale, title: r.title, mime: r.mime,
        size: Number(r.size), updatedAt: new Date(r.updated_at).toISOString(),
      }));
    },
    async getDailyAudio(track, day, locale) {
      const { rows } = await pool.query(
        'SELECT mime, bytes FROM daily_audio WHERE track = $1 AND day = $2 AND locale = $3', [track, day, locale]);
      return rows.length ? { mime: rows[0].mime, bytes: rows[0].bytes as Buffer } : null;
    },
    async upsertDailyAudio(a) {
      await pool.query(
        `INSERT INTO daily_audio (track, day, locale, title, mime, bytes, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6, now())
         ON CONFLICT (track, day, locale)
         DO UPDATE SET title = EXCLUDED.title, mime = EXCLUDED.mime, bytes = EXCLUDED.bytes, updated_at = now()`,
        [a.track, a.day, a.locale, a.title, a.mime, a.bytes]);
    },
    async deleteDailyAudio(track, day, locale) {
      await pool.query('DELETE FROM daily_audio WHERE track = $1 AND day = $2 AND locale = $3', [track, day, locale]);
    },
  };
}
