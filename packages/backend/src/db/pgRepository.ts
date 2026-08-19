/**
 * Postgres-backed Repository (TimescaleDB + PostGIS). Uses `pg`.
 * Geo queries mirror the examples in db/schema.sql. Kept thin: parameterised SQL,
 * no ORM. Health/location columns should be envelope-encrypted at the app layer
 * before reaching here in production (Data Privacy Officer).
 */

import { Pool } from 'pg';
import { computeChildrenStats } from '../analytics/childStats.js';
import { emergencyReason } from '../emergency/reason.js';
import { MAX_CODE_ATTEMPTS } from '../routes/phoneAuth.js';
import { normalizeSerial } from '../deviceSerial.js';
import type { ContentItemRow, DeviceRegistryRow, InventoryProduct, ShopOrderStatus, ShopProduct , SupportTicketRow, PurchaseOrder, PurchaseOrderStatus } from './repository';
import type {
  BandTelemetry,
  BpCalibration,
  ChildLocationFix,
  Geofence,
  GeofenceEvent,
  TriageSeverity,
} from '@fcs/shared';
import type { Repository } from './repository';
import { bundleDiscountMinor, markInStock } from './repository';
import { normalizePhone } from '../phone.js';
import { CRY_MIN_CONFIDENCE_DEFAULT } from '../cry/settings.js';
import { computeBiMetrics, type BiEventKind } from '../analytics/biMetrics.js';
import {
  BROADCAST_MIN_GAP_DAYS, INFANT_MAX_MONTHS, normalizeSegment,
  type BroadcastSegment,
} from '../admin/broadcasts.js';
import { DEFAULT_PREFS, FALLBACK_TZ } from '../notifications/gate.js';

/**
 * One purchase order out of its own row plus its item rows (migration 045).
 *
 * A free function rather than an inline map, because the list and the
 * single-order read must shape the answer identically — two copies of this
 * would drift the first time a column is added, and the panel would show a
 * field on one screen and «—» on the other.
 */
function purchaseOrderFromRows(
  o: Record<string, unknown>,
  items: Array<Record<string, unknown>>,
): PurchaseOrder {
  const iso = (v: unknown) => (v == null ? null : new Date(v as string).toISOString());
  return {
    id: o.id as string,
    supplierId: (o.supplier_id as string) ?? null,
    supplierName: (o.supplier_name as string) ?? null,
    supplierLeadTimeDays: o.supplier_lead_time_days == null ? null : Number(o.supplier_lead_time_days),
    status: o.status as PurchaseOrderStatus,
    placedAt: iso(o.placed_at),
    // A DATE, not a timestamp: nobody promises a shipment at 14:20. Kept as
    // the ten characters Postgres gives, so the panel prints the day it was
    // told rather than the day the reader's timezone shifts it to.
    expectedAt: o.expected_at == null
      ? null
      : (o.expected_at instanceof Date
          ? (o.expected_at as Date).toISOString().slice(0, 10)
          : String(o.expected_at).slice(0, 10)),
    note: (o.note as string) ?? null,
    createdBy: (o.created_by as string) ?? null,
    createdAt: iso(o.created_at)!,
    updatedAt: iso(o.updated_at)!,
    items: items.map((i) => ({
      variantId: i.variant_id as string,
      productId: i.product_id as string,
      productName: i.product_name as string,
      color: i.color as string,
      qtyOrdered: Number(i.qty_ordered),
      qtyReceived: Number(i.qty_received),
      unitCostMinor: i.unit_cost_minor == null ? null : Number(i.unit_cost_minor),
      receivedAt: iso(i.received_at),
    })),
  };
}

/**
 * The segment, as a WHERE clause over `users u`.
 *
 * The same three questions [matchesSegment] answers in TypeScript, and they
 * have to stay the same three: the in-memory repository is what every test and
 * every dev box runs on, so a difference here is a difference nothing catches
 * until a real broadcast reaches the wrong half of the country.
 *
 * `$1` is the short locale or NULL; `$2` is the audience.
 */
const SEGMENT_WHERE = `
  ($1::text IS NULL OR (CASE WHEN lower(coalesce(u.locale,'')) LIKE 'kk%' THEN 'kk' ELSE 'ru' END) = $1::text)
  AND (
    $2::text = 'all'
    -- Pregnant NOW. An overdue date is not a pregnancy the database can vouch
    -- for: she may have given birth and nobody told us.
    OR ($2::text = 'pregnant' AND u.due_date IS NOT NULL AND u.due_date >= CURRENT_DATE)
    -- A child with no recorded birthday still makes her a mother.
    OR ($2::text = 'mothers' AND EXISTS (
          SELECT 1 FROM children c WHERE c.guardian_id = u.id))
    OR ($2::text = 'infants' AND EXISTS (
          SELECT 1 FROM children c
           WHERE c.guardian_id = u.id
             AND c.date_of_birth IS NOT NULL
             AND c.date_of_birth <= CURRENT_DATE
             AND c.date_of_birth > CURRENT_DATE - INTERVAL '${INFANT_MAX_MONTHS} months'))
  )`;

/**
 * «Не чаще раза в неделю», as a NOT EXISTS.
 *
 * The interval is interpolated from a module constant, never from a request —
 * the panel's footer prints the same number, and one source keeps the sentence
 * on screen and the rule in the database from drifting apart.
 */
const IN_GAP = `
  EXISTS (
    SELECT 1 FROM broadcast_deliveries d
     WHERE d.user_id = u.id
       AND d.created_at >= now() - INTERVAL '${BROADCAST_MIN_GAP_DAYS} days')`;
const NOT_IN_GAP = `NOT ${IN_GAP}`;

/** [locale, audience] for [SEGMENT_WHERE]. */
function segmentParams(segment: BroadcastSegment): [string | null, string] {
  const s = normalizeSegment(segment);
  return [s.locale ?? null, s.audience ?? 'all'];
}

/** support_tickets row -> SupportTicketRow. One mapping, not six. */
function supportRow(r: Record<string, unknown>): SupportTicketRow {
  const iso = (v: unknown) => (v ? new Date(v as string).toISOString() : null);
  return {
    id: r.id as string,
    userId: (r.user_id as string) ?? null,
    phone: (r.phone as string) ?? null,
    customerName: (r.customer_name as string) ?? null,
    channel: r.channel as SupportTicketRow['channel'],
    subject: r.subject as string,
    body: (r.body as string) ?? '',
    status: r.status as SupportTicketRow['status'],
    assigneeId: (r.assignee_id as string) ?? null,
    createdAt: iso(r.created_at)!,
    updatedAt: iso(r.updated_at)!,
    answeredAt: iso(r.answered_at),
    closedAt: iso(r.closed_at),
    appContext: (r.app_context as string) ?? null,
    // Derived by the queries below (a lateral over support_replies), so a row
    // read through any other path says "she has not written back" rather than
    // claiming a time it did not fetch.
    lastCustomerAt: iso(r.last_customer_at),
    // When she last opened the thread (035). The app's badge counts answers
    // newer than this, so a row that forgot it would relight the badge on every
    // load.
    customerReadAt: iso(r.customer_read_at),
  };
}

/**
 * The columns every support read needs, plus when SHE last wrote.
 *
 * One string rather than three copies: the lateral is the part that is easy to
 * leave off, and a ticket list missing it would silently restart every SLA
 * clock at the ticket's creation date.
 */
const SUPPORT_COLS = `t.id, t.user_id, t.phone, t.customer_name, t.channel, t.subject,
        t.body, t.status, t.assignee_id, t.created_at, t.updated_at, t.answered_at,
        t.closed_at, t.app_context, t.customer_read_at, c.last_customer_at`;
const SUPPORT_FROM = `FROM support_tickets t
       LEFT JOIN LATERAL (
         SELECT max(r.at) AS last_customer_at
           FROM support_replies r
          WHERE r.ticket_id = t.id AND r.author = 'customer'
       ) c ON TRUE`;


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

/** One row of family_invites, as the Repository declares it. */
function inviteRow(r: Record<string, unknown>) {
  const iso = (v: unknown) => (v ? new Date(v as string).toISOString() : null);
  return {
    tokenHash: String(r.token_hash),
    ownerUserId: String(r.owner_user_id),
    level: String(r.level),
    label: (r.label ?? '') as string,
    createdAt: iso(r.created_at)!,
    expiresAt: iso(r.expires_at)!,
    usedAt: iso(r.used_at),
    usedBy: (r.used_by ?? null) as string | null,
    revokedAt: iso(r.revoked_at),
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
           (device_id, user_id, recorded_at, core_temp_c, skin_temp_c, device_temp_c, heart_rate_bpm,
            spo2_pct, systolic_mmhg, diastolic_mmhg, glucose_mmol, during_sleep, triage_severity)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
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
          // Its OWN column, never folded into core_temp_c: a device temperature
          // with no stated site is not an estimate of her core, and every
          // reader of core_temp_c treats that column as one. Storing it here
          // adds a row of data, not a second path back to a fever verdict.
          m.deviceTempC ?? null,
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
        // Stated, not selected: `device_id IS NULL` above is what MAKES the row
        // manual, so this is the WHERE clause spoken out loud. Without it the
        // app reads the restored row as a wrist estimate and the thermometer
        // reading she typed loses the one entitlement it has.
        source: 'manual' as const,
      }));
    },

    async recentEmergencyReadings(userId, aroundIso, windowMs) {
      const at = new Date(aroundIso);
      // A timestamp that will not parse cannot bound a range, and a NaN bound
      // makes the driver throw — on the path that decides whether an emergency
      // push goes out. No evidence, so no suppression: the caller pushes.
      if (Number.isNaN(at.getTime())) return [];
      const lo = new Date(at.getTime() - windowMs).toISOString();
      const hi = new Date(at.getTime() + windowMs).toISOString();
      const { rows } = await pool.query(
        // Both bounds inclusive; the caller drops the reading being judged by
        // its own timestamp rather than the SQL excluding it, so the rule lives
        // in one place and both repository implementations obey it identically.
        //
        // No LIMIT. The window is half an hour of one user's own readings, and
        // the partial answer a LIMIT would give is the dangerous direction here:
        // it decides "no episode yet" from a truncated list.
        `SELECT recorded_at, device_id IS NULL AS manual, core_temp_c, heart_rate_bpm,
                spo2_pct, systolic_mmhg, diastolic_mmhg, during_sleep
         FROM pregnancy_health_metrics
         WHERE user_id = $1 AND triage_severity = 'emergency'
           AND recorded_at >= $2 AND recorded_at <= $3
         ORDER BY recorded_at DESC`,
        [userId, lo, hi],
      );
      return rows.map((r) => ({
        recordedAt: new Date(r.recorded_at).toISOString(),
        manual: r.manual === true,
        coreTempC: r.core_temp_c ?? null,
        heartRateBpm: r.heart_rate_bpm ?? null,
        spo2Pct: r.spo2_pct ?? null,
        systolicMmHg: r.systolic_mmhg ?? null,
        diastolicMmHg: r.diastolic_mmhg ?? null,
        duringSleep: r.during_sleep === true,
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

    // ---- Family access (screen 40) ----

    async familyMembers(ownerUserId) {
      // The column is phone_e164; `u.phone` does not exist and threw on every
      // real Postgres, which the route then swallowed into an empty list — so
      // screen 40 showed no relatives and nobody could be revoked.
      const { rows } = await pool.query(
        `SELECT f.member_user_id, f.label, f.level, f.created_at,
                u.display_name, u.phone_e164
           FROM family_access f
           LEFT JOIN users u ON u.id = f.member_user_id
          WHERE f.owner_user_id = $1
          ORDER BY f.created_at DESC`,
        [ownerUserId],
      );
      return rows.map((r) => ({
        memberUserId: r.member_user_id,
        label: r.label ?? '',
        displayName: r.display_name ?? null,
        phone: r.phone_e164 ?? null,
        level: r.level,
        createdAt: new Date(r.created_at).toISOString(),
      }));
    },

    async familyMemberships(memberUserId) {
      const { rows } = await pool.query(
        `SELECT owner_user_id, level FROM family_access
          WHERE member_user_id = $1 ORDER BY created_at DESC`,
        [memberUserId],
      );
      return rows.map((r) => ({ ownerUserId: r.owner_user_id, level: r.level }));
    },

    async familyLevel(ownerUserId, memberUserId) {
      const { rows } = await pool.query(
        `SELECT level FROM family_access
          WHERE owner_user_id = $1 AND member_user_id = $2`,
        [ownerUserId, memberUserId],
      );
      return rows[0]?.level ?? null;
    },

    async upsertFamilyAccess(g) {
      // One row per pair: a second invitation accepted by the same person
      // re-levels rather than granting twice, so one revoke really revokes.
      await pool.query(
        `INSERT INTO family_access (owner_user_id, member_user_id, level, label)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (owner_user_id, member_user_id)
         DO UPDATE SET level = EXCLUDED.level, label = EXCLUDED.label`,
        [g.ownerUserId, g.memberUserId, g.level, g.label],
      );
    },

    async removeFamilyAccess(ownerUserId, memberUserId) {
      const { rowCount } = await pool.query(
        `DELETE FROM family_access
          WHERE owner_user_id = $1 AND member_user_id = $2`,
        [ownerUserId, memberUserId],
      );
      return (rowCount ?? 0) > 0;
    },

    async createFamilyInvite(i) {
      await pool.query(
        `INSERT INTO family_invites
           (owner_user_id, token_hash, level, label, expires_at)
         VALUES ($1,$2,$3,$4,$5)`,
        [i.ownerUserId, i.tokenHash, i.level, i.label, i.expiresAt],
      );
    },

    async familyInviteByHash(tokenHash) {
      const { rows } = await pool.query(
        `SELECT * FROM family_invites WHERE token_hash = $1`, [tokenHash]);
      return rows[0] ? inviteRow(rows[0]) : null;
    },

    async familyInvites(ownerUserId, limit) {
      const { rows } = await pool.query(
        `SELECT * FROM family_invites WHERE owner_user_id = $1
          ORDER BY created_at DESC LIMIT $2`,
        [ownerUserId, limit],
      );
      return rows.map(inviteRow);
    },

    async claimFamilyInvite(tokenHash, byUserId, atIso) {
      // The check and the claim are ONE statement. Reading the row, deciding it
      // is unused and then writing it is how two people accept one «одноразовая»
      // link from the same family chat within a second of each other — the
      // WHERE clause is what makes the second one lose.
      const { rowCount } = await pool.query(
        `UPDATE family_invites
            SET used_at = $3, used_by = $2
          WHERE token_hash = $1
            AND used_at IS NULL
            AND revoked_at IS NULL
            AND expires_at > $3`,
        [tokenHash, byUserId, atIso],
      );
      return (rowCount ?? 0) > 0;
    },

    async revokeFamilyInvite(ownerUserId, tokenHash) {
      const { rowCount } = await pool.query(
        `UPDATE family_invites SET revoked_at = now()
          WHERE owner_user_id = $1 AND token_hash = $2
            AND used_at IS NULL AND revoked_at IS NULL`,
        [ownerUserId, tokenHash],
      );
      return (rowCount ?? 0) > 0;
    },

    async locationHistory(childId, fromIso, toIso, limit) {
      // ASC: a trail is read in the order it was walked, and reversing 2 000
      // points in the route handler to draw a line is work the index already
      // did. idx_loc_child_time is (child_id, observed_at DESC), which serves
      // either direction.
      const { rows } = await pool.query(
        `SELECT child_id, observed_at, lat, lng, source, accuracy_m
           FROM location_history
          WHERE child_id = $1 AND observed_at >= $2 AND observed_at < $3
          ORDER BY observed_at ASC
          LIMIT $4`,
        [childId, fromIso, toIso, limit],
      );
      return rows.map((r) => ({
        childId: r.child_id,
        observedAt: new Date(r.observed_at).toISOString(),
        source: r.source,
        coords: {
          lat: Number(r.lat),
          lng: Number(r.lng),
          accuracyM: r.accuracy_m == null ? undefined : Number(r.accuracy_m),
        },
      }));
    },

    async pruneLocationHistory(cutoffIso) {
      // The DELETE that has lived in db/schema.sql as a comment since the
      // Timescale retention policy was dropped. A comment prunes nothing.
      const { rowCount } = await pool.query(
        'DELETE FROM location_history WHERE observed_at < $1', [cutoffIso]);
      return rowCount ?? 0;
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

    /**
     * The only place `last_seen` is ever written.
     *
     * Keyed on ble_mac like every other device lookup on the ingest path — the
     * id the payload carries is the physical one printed on the hardware.
     *
     * COALESCE on battery and firmware, so a telemetry item that carries
     * neither cannot blank what a wearable snapshot reported a minute ago.
     * Timestamps are compared with GREATEST for the same reason: batches
     * arrive out of order after an offline spell, and a stale one must not
     * drag «последний сигнал» backwards.
     */
    async touchDevice(deviceId, seen) {
      await pool.query(
        `UPDATE devices
            SET last_seen   = GREATEST($2::timestamptz, COALESCE(last_seen, $2::timestamptz)),
                battery_pct = COALESCE($3::int, battery_pct),
                firmware    = COALESCE($4::text, firmware)
          WHERE ble_mac = $1`,
        [deviceId, seen.at, seen.batteryPct ?? null, seen.firmware ?? null],
      );
    },

    /**
     * Frame 11's «Пометить браком» / «Снять пометку».
     *
     * Addressed by our own row id, not by the MAC: UNIQUE is (user_id,
     * ble_mac), so one MAC can exist under two accounts and a write keyed on
     * it would mark somebody else's device too.
     */
    async markDeviceDefect(deviceId, mark) {
      if (!looksLikeUuid(deviceId)) return false;
      const { rowCount } = await pool.query(
        `UPDATE devices SET defect_at = $2, defect_by = $3, defect_note = $4 WHERE id = $1`,
        [deviceId, mark?.at ?? null, mark?.by ?? null, mark?.note ?? null],
      );
      return (rowCount ?? 0) > 0;
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
    async listGeofenceEvents(childId, limit, fromIso, toIso) {
      // Built up rather than interpolated, like stockMoves: two optional
      // conditions with hard-coded $3/$4 is how one bound ends up reading the
      // other one's value.
      //
      // The WHERE runs before the LIMIT, which is the entire point — the day
      // must be chosen by the database, not by a filter over rows it already
      // dropped. idx_gfevents_child_time (child_id, occurred_at DESC) serves
      // this exactly: equality on the leading column, a range on the second,
      // and the ORDER BY satisfied by the index order.
      const params: unknown[] = [childId, limit];
      const where: string[] = ['ge.child_id = $1'];
      if (fromIso) { params.push(fromIso); where.push(`ge.occurred_at >= $${params.length}`); }
      if (toIso) { params.push(toIso); where.push(`ge.occurred_at < $${params.length}`); }
      const { rows } = await pool.query(
        `SELECT ge.child_id, ge.geofence_id, g.name AS geofence_name, ge.transition, ge.source, ge.occurred_at
         FROM geofence_events ge JOIN geofences g ON g.id = ge.geofence_id
         WHERE ${where.join(' AND ')} ORDER BY ge.occurred_at DESC LIMIT $2`, params);
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
      // The vitals come back with the row now. They were already in the table
      // and already indexed by this query's plan; not selecting them is what
      // forced `code: 'EMERGENCY'` on every line of the feed.
      const { rows } = await pool.query(
        `SELECT m.user_id, u.display_name, m.triage_severity, m.recorded_at,
                m.heart_rate_bpm, m.spo2_pct, m.systolic_mmhg, m.diastolic_mmhg,
                m.core_temp_c, m.during_sleep
         FROM pregnancy_health_metrics m JOIN users u ON u.id = m.user_id
         WHERE m.triage_severity = 'emergency' ORDER BY m.recorded_at DESC LIMIT $1`, [limit]);
      // The hypertable has no single-column id, so an emergency's identity is
      // (user, time). Compute it here so it matches between the list and the ack.
      const emergencies = rows.map((r) => {
        const reason = emergencyReason({
          heartRateBpm: r.heart_rate_bpm === null ? null : Number(r.heart_rate_bpm),
          spo2Pct: r.spo2_pct === null ? null : Number(r.spo2_pct),
          systolicMmHg: r.systolic_mmhg === null ? null : Number(r.systolic_mmhg),
          diastolicMmHg: r.diastolic_mmhg === null ? null : Number(r.diastolic_mmhg),
          coreTempC: r.core_temp_c === null ? null : Number(r.core_temp_c),
          duringSleep: r.during_sleep === true,
        });
        return {
          id: `${r.user_id}|${new Date(r.recorded_at).toISOString()}`,
          userId: r.user_id as string,
          displayName: r.display_name as string,
          ...reason,
          severity: r.triage_severity as string,
          at: new Date(r.recorded_at).toISOString(),
        };
      });
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
      // Phone was NOT searched, while the box above it said «Поиск по имени или
      // телефону…» and the table drew a phone column. An operator with a
      // customer on the line pasted «+7 701 118 90 12», got «Никто не найден»,
      // and told a real person she had no account.
      //
      // Matched on DIGITS, both sides. She types what is written on a parcel —
      // spaces, brackets, a leading +7 or 8 — and the column holds E.164. A
      // literal ILIKE would have been a phone search that still missed.
      //
      // Four digits minimum: fewer turns every query into a scan of everyone
      // whose number contains «77», which is not a search result, it is the
      // whole table.
      const digits = q.replace(/\D+/g, '');
      const phoneLike = digits.length >= 4 ? `%${digits}%` : null;
      const where = `display_name ILIKE $1 OR email ILIKE $1
         OR ($2::text IS NOT NULL AND regexp_replace(coalesce(phone_e164,''), '[^0-9]', '', 'g') LIKE $2)`;
      const total = await pool.query(
        `SELECT count(*)::int AS n FROM users WHERE ${where}`, [like, phoneLike]);
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
            OR ($4::text IS NOT NULL AND regexp_replace(coalesce(u.phone_e164,''), '[^0-9]', '', 'g') LIKE $4)
         ORDER BY u.created_at DESC LIMIT $2 OFFSET $3`,
        [like, limit, offset, phoneLike]);
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
      await pool.query(`INSERT INTO audit_log (staff_id, action, target, reason) VALUES ($1,$2,$3,$4)`,
        [entry.staffId, entry.action, entry.target ?? null, entry.reason ?? null]);
    },
    async listAudit(limit, offset = 0) {
      // Joined to the roster on both ends. The log's whole purpose is "who
      // looked at this mother's data", and it answered that with a UUID —
      // which nobody can read, and which the panel then printed verbatim.
      //
      // LEFT JOIN, and the id is still returned: entries written before there
      // were accounts (or by an account since removed) must stay visible.
      // Dropping them would make the log lie by omission.
      //
      // LIMIT $1 is asked for limit + 1: the surplus row is never returned, it
      // only answers "is there another page". That is the whole reason this
      // does not run count(*) — see AuditPage in repository.ts. One extra row
      // on an indexed read, instead of a full scan of an append-only table
      // with no upper bound, on every open of the tab.
      //
      // ORDER BY at DESC, id DESC — a tiebreak, not decoration. `at` defaults
      // to now(), so two rows written inside one request share it exactly, and
      // an unspecified order among equals is free to differ between the query
      // for page one and the query for page two. A row that moves across the
      // boundary is a row a reviewer sees twice, or never.
      const { rows } = await pool.query(
        `SELECT l.staff_id, l.action, l.target, l.reason, l.at,
                a.display_name AS staff_name, a.phone AS staff_phone,
                t.display_name AS target_name, t.phone AS target_phone
           FROM audit_log l
           LEFT JOIN staff_accounts a ON a.id::text = l.staff_id
           LEFT JOIN staff_accounts t ON t.id::text = l.target
          ORDER BY l.at DESC, l.id DESC
          LIMIT $1 OFFSET $2`,
        [limit + 1, Math.max(0, offset)],
      );
      const hasMore = rows.length > limit;
      return {
        hasMore,
        entries: rows.slice(0, limit).map((r) => ({
          staffId: r.staff_id,
          staffName: r.staff_name ?? null,
          staffPhone: r.staff_phone ?? null,
          action: r.action,
          target: r.target,
          targetName: r.target_name ?? null,
          reason: r.reason ?? null,
          at: new Date(r.at).toISOString(),
        })),
      };
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
        // firmware was declared in the schema and SELECTed by nothing, so frame
        // 11 could not show the column the spec asks for by name. The defect
        // marks come back with it so the fleet row can say «брак» without a
        // second request per row.
        `SELECT d.id, d.ble_mac, d.name, d.kind, d.user_id, d.battery_pct, d.last_seen,
                d.firmware, d.defect_at, d.defect_by, d.defect_note,
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
        // Carried alongside, because a WRITE cannot be addressed by the MAC:
        // UNIQUE is (user_id, ble_mac), so the same unit resold to a second
        // family is two rows with one MAC.
        deviceId: r.id,
        displayName: r.display_name ?? '', childName: r.child_name ?? null,
        batteryPct: r.battery_pct === null ? null : Number(r.battery_pct),
        lastSeen: r.last_seen ? new Date(r.last_seen).toISOString() : null,
        firmware: r.firmware ?? null,
        defectAt: r.defect_at ? new Date(r.defect_at).toISOString() : null,
        defectBy: r.defect_by ?? null,
        defectNote: r.defect_note ?? null,
      }));
    },

    async adminSafetyEvents(limit) {
      // `outcome` and the mother's phone join the row. Both existed already —
      // the column since migration 032, the number since sign-in — and neither
      // was selected, so the panel drew «Чем закончилось» from `undefined` and
      // its four-step instruction told an operator to call a number that was
      // nowhere on the screen.
      const { rows } = await pool.query(
        `SELECT a.user_id, a.kind, a.zone_name, a.at, a.outcome,
                u.display_name, u.phone_e164, c.name AS child_name
           FROM safety_alerts a
           JOIN users u ON u.id = a.user_id
           LEFT JOIN children c ON c.id = a.child_id
          ORDER BY a.at DESC LIMIT $1`, [limit]);
      return rows.map((r) => ({
        userId: r.user_id, displayName: r.display_name ?? '',
        childName: r.child_name ?? '', kind: r.kind, zoneName: r.zone_name,
        at: new Date(r.at).toISOString(),
        // Only an SOS can be closed. A crossing with a stray value in the
        // column would still print as an outcome, so it is dropped here.
        outcome: r.kind === 'sos' ? (r.outcome ?? null) : null,
        phone: r.phone_e164 ?? null,
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
                 count(*) FILTER (WHERE kind = 'tag' AND child_id IS NULL) AS unassigned,
                 -- Paired, but not one of ours. The MAC is normalised on BOTH
                 -- sides of the comparison for the same reason the registry
                 -- normalises on the way in: a device counted as grey-market
                 -- because the warehouse typed dashes and the phone reported
                 -- colons is a number that would send somebody hunting a
                 -- problem that does not exist.
                 count(*) FILTER (
                   WHERE UPPER(REGEXP_REPLACE(ble_mac, '[^0-9A-Za-z]', '', 'g'))
                     NOT IN (SELECT serial FROM device_registry)
                 ) AS unregistered
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
          unregistered: n(d.unregistered),
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

    // ---- Pregnancy calendar overrides (frames 14a / 14b) ----
    async pregnancyWeekOverrides() {
      const { rows } = await pool.query(
        `SELECT week, length_cm, hcg, ru, kk, draft, review, rev, updated_at, updated_by
           FROM pregnancy_week_overrides ORDER BY week`);
      return rows.map((r) => ({
        week: Number(r.week),
        // NULL means "keep the contract's value", and it has to survive the
        // round trip as null rather than '' — an empty string would blank the
        // length chip on every week anybody ever edited.
        lengthCm: r.length_cm ?? null,
        hcg: r.hcg ?? null,
        ru: r.ru as { baby: string; you: string; recommend: string },
        kk: r.kk as { baby: string; you: string; recommend: string },
        draft: r.draft === true,
        review: (r.review ?? null) as { by: string; at: string; fingerprint: string } | null,
        rev: Number(r.rev ?? 1),
        updatedAt: new Date(r.updated_at).toISOString(),
        updatedBy: r.updated_by ?? null,
      }));
    },

    async putPregnancyWeekOverride(v) {
      // rev = existing + 1 rather than a supplied value: the counter is the
      // store's, and the served calendar's version is built from it, so a
      // caller must not be able to hold it still while changing the text.
      await pool.query(
        `INSERT INTO pregnancy_week_overrides
           (week, length_cm, hcg, ru, kk, draft, review, rev, updated_at, updated_by)
         VALUES ($1,$2,$3,$4::jsonb,$5::jsonb,$6,$7::jsonb,1,now(),$8)
         ON CONFLICT (week) DO UPDATE SET
           length_cm = EXCLUDED.length_cm,
           hcg       = EXCLUDED.hcg,
           ru        = EXCLUDED.ru,
           kk        = EXCLUDED.kk,
           draft     = EXCLUDED.draft,
           review    = EXCLUDED.review,
           rev       = pregnancy_week_overrides.rev + 1,
           updated_at = now(),
           updated_by = EXCLUDED.updated_by`,
        [v.week, v.lengthCm, v.hcg, JSON.stringify(v.ru), JSON.stringify(v.kk),
          v.draft, v.review ? JSON.stringify(v.review) : null, v.updatedBy]);
    },

    // ---- Emergency-help overrides (frame 16b → app screen 37) ----
    async emergencyHelpOverrides() {
      const { rows } = await pool.query(
        `SELECT id, severity, sort, ru, kk, draft, review, rev, updated_at, updated_by
           FROM emergency_help_overrides ORDER BY id`);
      return rows.map((r) => ({
        id: r.id as string,
        severity: r.severity as 'red' | 'amber',
        sort: Number(r.sort ?? 0),
        ru: r.ru as { title: string; what: string; do: string },
        kk: r.kk as { title: string; what: string; do: string },
        draft: r.draft === true,
        review: (r.review ?? null) as { by: string; at: string; fingerprint: string } | null,
        rev: Number(r.rev ?? 1),
        updatedAt: new Date(r.updated_at).toISOString(),
        updatedBy: r.updated_by ?? null,
      }));
    },

    async putEmergencyHelpOverride(v) {
      // rev = existing + 1 rather than a supplied value: the counter is the
      // store's, and the served list's version is built from it, so a caller
      // must not be able to hold it still while changing the text.
      await pool.query(
        `INSERT INTO emergency_help_overrides
           (id, severity, sort, ru, kk, draft, review, rev, updated_at, updated_by)
         VALUES ($1,$2,$3,$4::jsonb,$5::jsonb,$6,$7::jsonb,1,now(),$8)
         ON CONFLICT (id) DO UPDATE SET
           severity  = EXCLUDED.severity,
           sort      = EXCLUDED.sort,
           ru        = EXCLUDED.ru,
           kk        = EXCLUDED.kk,
           draft     = EXCLUDED.draft,
           review    = EXCLUDED.review,
           rev       = emergency_help_overrides.rev + 1,
           updated_at = now(),
           updated_by = EXCLUDED.updated_by`,
        [v.id, v.severity, v.sort, JSON.stringify(v.ru), JSON.stringify(v.kk),
          v.draft, v.review ? JSON.stringify(v.review) : null, v.updatedBy]);
    },

    // ---- Vaccination schedule overrides (frames 15 / 15a / 15b) ----
    async vaccinationOverrides() {
      const { rows } = await pool.query(
        `SELECT key, vaccine_id, at_month, dose, ru, kk, added, draft, review, rev,
                updated_at, updated_by
           FROM vaccination_overrides ORDER BY key`);
      return rows.map((r) => ({
        key: r.key as string,
        id: r.vaccine_id as string,
        atMonth: Number(r.at_month),
        // NULL is the dose of a single-shot vaccine and has to survive the round
        // trip as null: `Number(null)` is 0, and a BCG at "dose 0" would key as
        // `bcg/0` and match nothing a mother has ever ticked.
        dose: r.dose == null ? null : Number(r.dose),
        ru: r.ru as { name: string; note: string },
        kk: r.kk as { name: string; note: string },
        added: r.added === true,
        draft: r.draft === true,
        review: (r.review ?? null) as { by: string; at: string; fingerprint: string } | null,
        rev: Number(r.rev ?? 1),
        updatedAt: new Date(r.updated_at).toISOString(),
        updatedBy: r.updated_by ?? null,
      }));
    },

    async putVaccinationOverride(v) {
      const after = {
        key: v.key, id: v.id, atMonth: v.atMonth, dose: v.dose,
        ru: v.ru, kk: v.kk, added: v.added, draft: v.draft, review: v.review,
      };
      // ONE statement, so the log entry cannot be lost while the row it
      // describes is written — frame 15b is the only record of what a schedule
      // used to say, and a history with holes is worse than none.
      //
      // `prev` is evaluated against the snapshot the statement started from, so
      // it is genuinely the row BEFORE this write even though the same
      // statement replaces it.
      //
      // The ON CONFLICT list deliberately omits vaccine_id, dose and added:
      // those are identity. A save that could move them would re-key a row
      // whose key is what every `child_vaccines` tick is filed under.
      await pool.query(
        `WITH prev AS (
           SELECT jsonb_build_object(
             'key', key, 'id', vaccine_id, 'atMonth', at_month, 'dose', dose,
             'ru', ru, 'kk', kk, 'added', added, 'draft', draft, 'review', review
           ) AS snap
             FROM vaccination_overrides WHERE key = $1
         ), up AS (
           INSERT INTO vaccination_overrides
             (key, vaccine_id, at_month, dose, ru, kk, added, draft, review, rev, updated_at, updated_by)
           VALUES ($1,$2,$3,$4,$5::jsonb,$6::jsonb,$7,$8,$9::jsonb,1,now(),$10)
           ON CONFLICT (key) DO UPDATE SET
             at_month   = EXCLUDED.at_month,
             ru         = EXCLUDED.ru,
             kk         = EXCLUDED.kk,
             draft      = EXCLUDED.draft,
             review     = EXCLUDED.review,
             rev        = vaccination_overrides.rev + 1,
             updated_at = now(),
             updated_by = EXCLUDED.updated_by
           RETURNING 1
         )
         INSERT INTO vaccination_schedule_log (key, before, after, actor)
         SELECT $1, (SELECT snap FROM prev), $11::jsonb, $10
           FROM up`,
        [v.key, v.id, v.atMonth, v.dose, JSON.stringify(v.ru), JSON.stringify(v.kk),
          v.added, v.draft, v.review ? JSON.stringify(v.review) : null, v.updatedBy,
          JSON.stringify(after)]);
    },

    async vaccinationSettings() {
      const { rows } = await pool.query(
        `SELECT due_window_months, rev, updated_at, updated_by FROM vaccination_settings WHERE id`);
      const r = rows[0];
      // No row is not "1 month": it is «никто не менял», which the panel prints
      // differently and which stops the served version from counting a decision
      // nobody took.
      if (!r) return null;
      return {
        dueWindowMonths: Number(r.due_window_months),
        rev: Number(r.rev ?? 1),
        updatedAt: new Date(r.updated_at).toISOString(),
        updatedBy: r.updated_by ?? null,
      };
    },

    async putVaccinationSettings(v) {
      await pool.query(
        `WITH prev AS (
           SELECT jsonb_build_object('dueWindowMonths', due_window_months) AS snap
             FROM vaccination_settings WHERE id
         ), up AS (
           INSERT INTO vaccination_settings (id, due_window_months, rev, updated_at, updated_by)
           VALUES (TRUE, $1, 1, now(), $2)
           ON CONFLICT (id) DO UPDATE SET
             due_window_months = EXCLUDED.due_window_months,
             rev               = vaccination_settings.rev + 1,
             updated_at        = now(),
             updated_by        = EXCLUDED.updated_by
           RETURNING 1
         )
         INSERT INTO vaccination_schedule_log (key, before, after, actor)
         SELECT '@settings', (SELECT snap FROM prev),
                jsonb_build_object('dueWindowMonths', $1::int), $2
           FROM up`,
        [v.dueWindowMonths, v.updatedBy]);
    },

    async vaccinationScheduleLog(limit) {
      const { rows } = await pool.query(
        `SELECT id, key, before, after, actor, at
           FROM vaccination_schedule_log ORDER BY at DESC, id DESC LIMIT $1`, [limit]);
      return rows.map((r) => ({
        id: Number(r.id),
        key: r.key as string,
        before: (r.before ?? null) as Record<string, unknown> | null,
        after: (r.after ?? {}) as Record<string, unknown>,
        actor: r.actor ?? null,
        at: new Date(r.at).toISOString(),
      }));
    },

    async vaccinationCoverage() {
      // Completed months, by the calendar, matching ageInMonths() in the app and
      // the `m<n>` buckets the dashboard already uses: whole months, with the
      // day of the month having to come round. `age()` returns an interval, and
      // extracting years*12 + months off it is exactly that.
      const AGE_MONTHS = `(EXTRACT(YEAR FROM age(CURRENT_DATE, c.date_of_birth)) * 12
                         + EXTRACT(MONTH FROM age(CURRENT_DATE, c.date_of_birth)))::int`;
      const [ages, ticks, nodob] = await Promise.all([
        pool.query(
          `SELECT ${AGE_MONTHS} AS age_months, count(*)::int AS n
             FROM children c
            WHERE c.date_of_birth IS NOT NULL AND c.date_of_birth <= CURRENT_DATE
            GROUP BY 1`),
        // Grouped by (key, age) rather than by key alone so the caller can drop
        // a tick from a child too young to be in the denominator. Without that
        // one organised parent ticking a shot off early prints 110 % coverage.
        pool.query(
          `SELECT v.vaccine_key AS key, ${AGE_MONTHS} AS age_months, count(*)::int AS n
             FROM child_vaccines v JOIN children c ON c.id = v.child_id
            WHERE c.date_of_birth IS NOT NULL AND c.date_of_birth <= CURRENT_DATE
            GROUP BY 1, 2`),
        // Counted and reported, never folded into a denominator: a child with
        // no birth date cannot be placed on the calendar at all, and silently
        // treating her as un-vaccinated would depress every figure on the screen.
        pool.query(
          `SELECT count(*)::int AS n FROM children
            WHERE date_of_birth IS NULL OR date_of_birth > CURRENT_DATE`),
      ]);
      return {
        childAges: ages.rows.map((r) => ({ ageMonths: Number(r.age_months), n: Number(r.n) })),
        ticks: ticks.rows.map((r) => ({
          key: r.key as string, ageMonths: Number(r.age_months), n: Number(r.n),
        })),
        childrenWithoutDob: Number(nodob.rows[0]?.n ?? 0),
      };
    },

    async pregnancyWeekMotherCounts() {
      // The same expression the dashboard's stage histogram uses, so «неделя 22»
      // means one thing across the back office. Integer division on two `date`
      // columns is whole days; GREATEST/LEAST clamps into the calendar's range.
      //
      // `due_date >= CURRENT_DATE` excludes overdue mothers on purpose: an edit
      // to week 40 no longer reaches them first, and folding them in would
      // inflate the number the editor is being asked to trust.
      const { rows } = await pool.query(
        `SELECT GREATEST(1, LEAST(40, 40 - ((due_date - CURRENT_DATE) / 7)))::int AS week,
                count(*)::int AS n
           FROM users
          WHERE due_date IS NOT NULL AND due_date >= CURRENT_DATE
          GROUP BY 1`);
      const out: Record<number, number> = {};
      for (const r of rows) out[Number(r.week)] = Number(r.n);
      return out;
    },

    // ---- Broadcasts (frame 06 «Маркетинг») ----
    async listBroadcasts(limit) {
      const { rows } = await pool.query(
        // `delivered` off the ledger, not off a stored counter: a number that
        // can disagree with the rows it counts is a number somebody will
        // eventually quote in a meeting.
        `SELECT b.id, b.title_ru, b.body_ru, b.title_kk, b.body_kk, b.segment, b.status,
                b.created_by, b.created_at, b.updated_at, b.published_at,
                (SELECT count(*)::int FROM broadcast_deliveries d WHERE d.broadcast_id = b.id) AS delivered
           FROM broadcasts b
          ORDER BY b.created_at DESC
          LIMIT $1`,
        [limit]);
      return rows.map((r) => ({
        id: r.id as string,
        titleRu: r.title_ru as string,
        bodyRu: r.body_ru as string,
        titleKk: (r.title_kk ?? null) as string | null,
        bodyKk: (r.body_kk ?? null) as string | null,
        segment: normalizeSegment(r.segment),
        status: r.status === 'published' ? 'published' as const : 'draft' as const,
        createdBy: (r.created_by ?? null) as string | null,
        createdAt: new Date(r.created_at).toISOString(),
        updatedAt: new Date(r.updated_at).toISOString(),
        publishedAt: r.published_at ? new Date(r.published_at).toISOString() : null,
        delivered: Number(r.delivered ?? 0),
      }));
    },

    async saveBroadcast(v) {
      // `WHERE broadcasts.status = 'draft'` on the UPDATE half: a published
      // broadcast is already on somebody's phone, and rewriting the row would
      // change what the panel says we sent without changing what we sent.
      // Reported rather than silently ignored — the route turns 0 rows into a
      // sentence.
      const { rowCount } = await pool.query(
        `INSERT INTO broadcasts
           (id, title_ru, body_ru, title_kk, body_kk, segment, status, created_by, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6::jsonb,'draft',$7,now(),now())
         ON CONFLICT (id) DO UPDATE SET
           title_ru = EXCLUDED.title_ru,
           body_ru  = EXCLUDED.body_ru,
           title_kk = EXCLUDED.title_kk,
           body_kk  = EXCLUDED.body_kk,
           segment  = EXCLUDED.segment,
           updated_at = now()
         WHERE broadcasts.status = 'draft'`,
        [v.id, v.titleRu, v.bodyRu, v.titleKk, v.bodyKk,
          JSON.stringify(normalizeSegment(v.segment)), v.createdBy]);
      if (!rowCount) throw new Error('broadcast_already_published');
    },

    async broadcastAudience(segment) {
      const { rows } = await pool.query(
        `SELECT count(*)::int AS matched,
                count(*) FILTER (WHERE ${IN_GAP})::int AS excluded
           FROM users u
          WHERE ${SEGMENT_WHERE}`,
        segmentParams(segment));
      return { matched: Number(rows[0]?.matched ?? 0), excluded: Number(rows[0]?.excluded ?? 0) };
    },

    async publishBroadcast(id) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const found = await client.query(
          `SELECT segment FROM broadcasts WHERE id = $1 FOR UPDATE`, [id]);
        if (found.rowCount === 0) {
          await client.query('ROLLBACK');
          return null;
        }
        const params = segmentParams(normalizeSegment(found.rows[0].segment));
        // Matched and delivered are counted in the SAME transaction, so the
        // difference between them is the weekly gap and never a race.
        const matched = await client.query(
          `SELECT count(*)::int AS n FROM users u WHERE ${SEGMENT_WHERE}`, params);
        const sent = await client.query(
          `INSERT INTO broadcast_deliveries (broadcast_id, user_id)
           SELECT $3, u.id FROM users u
            WHERE ${SEGMENT_WHERE} AND ${NOT_IN_GAP}
           ON CONFLICT DO NOTHING
           RETURNING user_id`,
          [...params, id]);
        await client.query(
          `UPDATE broadcasts SET status = 'published', published_at = now(), updated_at = now()
            WHERE id = $1`, [id]);
        await client.query('COMMIT');
        const userIds = sent.rows.map((r) => r.user_id as string);
        return {
          matched: Number(matched.rows[0]?.n ?? 0),
          excluded: Number(matched.rows[0]?.n ?? 0) - userIds.length,
          delivered: userIds.length,
          userIds,
        };
      } catch (e) {
        await client.query('ROLLBACK').catch(() => {});
        throw e;
      } finally {
        client.release();
      }
    },

    async listAnnouncements(userId, limit) {
      const { rows } = await pool.query(
        // `d.created_at`, not `b.published_at`: what she wants to see is when
        // it reached HER, and a re-published broadcast can reach two people on
        // two different days.
        `SELECT b.id, b.title_ru, b.body_ru, b.title_kk, b.body_kk, d.created_at
           FROM broadcast_deliveries d
           JOIN broadcasts b ON b.id = d.broadcast_id
          WHERE d.user_id = $1 AND b.status = 'published'
          ORDER BY d.created_at DESC
          LIMIT $2`,
        [userId, limit]);
      return rows.map((r) => ({
        id: r.id as string,
        at: new Date(r.created_at).toISOString(),
        ru: { title: r.title_ru as string, body: r.body_ru as string },
        // Publication is refused without the Kazakh half, so a published row
        // always has one. The fallback is for rows written before that rule.
        kk: {
          title: (r.title_kk ?? r.title_ru) as string,
          body: (r.body_kk ?? r.body_ru) as string,
        },
      }));
    },

    // ---- Notifications (frame 25 «Уведомления») ----
    //
    // The join is the whole point of the first query: the switches live in
    // notification_prefs and the CLOCK they are read against lives in
    // users.timezone, and fetching them separately is how one of the two gets
    // forgotten. A LEFT JOIN, because most accounts have no prefs row — and
    // COALESCE fills the defaults so a missing row can never read as «она
    // отключила».
    async getNotificationPrefs(userId) {
      const { rows } = await pool.query(
        `SELECT u.timezone,
                COALESCE(p.zone_events, TRUE) AS zone_events,
                COALESCE(p.check_in,    TRUE) AS check_in,
                COALESCE(p.low_battery, TRUE) AS low_battery,
                COALESCE(p.updates,     TRUE) AS updates,
                p.quiet_start, p.quiet_end, p.updated_at
           FROM users u
           LEFT JOIN notification_prefs p ON p.user_id = u.id
          WHERE u.id = $1`,
        [userId]);
      const r = rows[0];
      // No user row at all — a deleted account, a stale token. Defaults, never
      // an exception: a push path that throws when it cannot read preferences
      // is a push path that stops sending emergencies.
      if (!r) return { ...DEFAULT_PREFS, timezone: FALLBACK_TZ, updatedAt: null };
      const s = r.quiet_start == null ? null : Number(r.quiet_start);
      const e = r.quiet_end == null ? null : Number(r.quiet_end);
      return {
        zoneEvents: r.zone_events as boolean,
        checkIn: r.check_in as boolean,
        lowBattery: r.low_battery as boolean,
        updates: r.updates as boolean,
        // Half a window is no window — same tolerance as the app and the gate.
        quietStart: s != null && e != null ? s : null,
        quietEnd: s != null && e != null ? e : null,
        timezone: (r.timezone as string) || FALLBACK_TZ,
        updatedAt: r.updated_at ? new Date(r.updated_at).toISOString() : null,
      };
    },

    async putNotificationPrefs(userId, prefs) {
      const both = prefs.quietStart != null && prefs.quietEnd != null;
      await pool.query(
        `INSERT INTO notification_prefs
           (user_id, zone_events, check_in, low_battery, updates, quiet_start, quiet_end, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7, now())
         ON CONFLICT (user_id) DO UPDATE
           SET zone_events = EXCLUDED.zone_events,
               check_in    = EXCLUDED.check_in,
               low_battery = EXCLUDED.low_battery,
               updates     = EXCLUDED.updates,
               quiet_start = EXCLUDED.quiet_start,
               quiet_end   = EXCLUDED.quiet_end,
               updated_at  = now()`,
        [userId, prefs.zoneEvents, prefs.checkIn, prefs.lowBattery, prefs.updates,
          both ? prefs.quietStart : null, both ? prefs.quietEnd : null]);
    },

    /// The write side of `users.timezone` — the column getNotificationPrefs
    /// joins in above and, until this existed, nothing anywhere set. The
    /// column is NOT NULL DEFAULT 'Asia/Almaty', so a row that has never been
    /// told keeps that default rather than going null.
    async setUserTimezone(userId, timezone) {
      await pool.query(`UPDATE users SET timezone = $2 WHERE id = $1`, [userId, timezone]);
    },

    /// Never lets a bookkeeping failure become a delivery failure — see the
    /// caller in notifications/dispatch.ts, which swallows this on purpose.
    async recordPushDelivery(row) {
      await pool.query(
        `INSERT INTO push_deliveries (user_id, kind, sent, failed, dead, held_reason, error)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [row.userId, row.kind, row.sent, row.failed, row.dead, row.heldReason, row.error]);
    },

    async pushDeliverySummary(days) {
      const window = Math.max(1, Math.trunc(days));
      const [{ rows: kinds }, { rows: prefRows }, { rows: lastRows }] = await Promise.all([
        pool.query(
          // FILTER rather than five round trips, and every column a count of
          // rows that exist. Nothing here is derived from a rate.
          `SELECT kind,
                  count(*)::int                                            AS attempts,
                  COALESCE(sum(sent), 0)::int                              AS delivered,
                  COALESCE(sum(failed), 0)::int                            AS failed,
                  COALESCE(sum(dead), 0)::int                              AS dead,
                  count(*) FILTER (WHERE held_reason IS NOT NULL)::int      AS held,
                  count(*) FILTER (WHERE held_reason = 'muted')::int        AS held_muted,
                  count(*) FILTER (WHERE held_reason = 'quiet_hours')::int  AS held_quiet,
                  count(*) FILTER (WHERE error = 'no_tokens')::int          AS no_tokens,
                  count(*) FILTER (WHERE error IS NOT NULL AND error <> 'no_tokens')::int AS errors
             FROM push_deliveries
            WHERE at >= now() - make_interval(days => $1::int)
            GROUP BY kind
            ORDER BY kind`,
          [window]),
        pool.query(
          `SELECT count(*)::int                                              AS configured,
                  count(*) FILTER (WHERE NOT zone_events)::int               AS zone_events,
                  count(*) FILTER (WHERE NOT check_in)::int                  AS check_in,
                  count(*) FILTER (WHERE NOT low_battery)::int               AS low_battery,
                  count(*) FILTER (WHERE NOT updates)::int                   AS updates,
                  count(*) FILTER (WHERE quiet_start IS NOT NULL
                                     AND quiet_end IS NOT NULL
                                     AND quiet_start <> quiet_end)::int      AS quiet_hours
             FROM notification_prefs`),
        pool.query(
          `SELECT max(at) AS last_at FROM push_deliveries
            WHERE at >= now() - make_interval(days => $1::int)`,
          [window]),
      ]);
      const p = prefRows[0] ?? {};
      const kindRows = kinds.map((r) => ({
        kind: r.kind as string,
        attempts: Number(r.attempts),
        delivered: Number(r.delivered),
        failed: Number(r.failed),
        noTokens: Number(r.no_tokens),
        held: Number(r.held),
        heldMuted: Number(r.held_muted),
        heldQuiet: Number(r.held_quiet),
        errors: Number(r.errors),
        dead: Number(r.dead),
      }));
      return {
        windowDays: window,
        kinds: kindRows,
        deadTokens: kindRows.reduce((n, k) => n + k.dead, 0),
        muted: {
          zoneEvents: Number(p.zone_events ?? 0),
          checkIn: Number(p.check_in ?? 0),
          lowBattery: Number(p.low_battery ?? 0),
          updates: Number(p.updates ?? 0),
          quietHours: Number(p.quiet_hours ?? 0),
          configured: Number(p.configured ?? 0),
        },
        lastAt: lastRows[0]?.last_at ? new Date(lastRows[0].last_at).toISOString() : null,
      };
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

    // ---- Watch activity / wellbeing days ----
    /**
     * The id the watch reports is its MAC; `wearable_days.device_id` is a UUID
     * FK to devices(id).
     *
     * This bound the MAC straight into $2 and would have raised 22P02 —
     * «invalid input syntax for type uuid» — on the first real snapshot from a
     * real Postgres. handleIngestBatch catches per item, so the failure would
     * have surfaced as `rejected`, the batcher would have resent the same
     * batch for ever, and nothing would ever have been stored. Every test
     * passed, because the in-memory repository has no types.
     *
     * The SELECT resolves the row the ingest path has already proven the
     * caller owns; no matching device inserts nothing rather than inventing a
     * parent row.
     */
    async upsertWearableDay(row) {
      await pool.query(
        `INSERT INTO wearable_days (
           user_id, device_id, day, recorded_at, steps, kcal, meters,
           sleep_min, deep_sleep_min, light_sleep_min,
           stress, breath_rate, met, battery_pct, charging, worn,
           hr_avg, hr_min, hr_max, spo2_avg, spo2_min,
           systolic_avg, diastolic_avg, temp_avg_tenths, blood_sugar_tenths)
         SELECT $1, d.id, $3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,
                $17,$18,$19,$20,$21,$22,$23,$24,$25
           FROM devices d WHERE d.user_id = $1 AND d.ble_mac = $2
         ON CONFLICT (user_id, device_id, day) DO UPDATE
           SET recorded_at = EXCLUDED.recorded_at,
               steps = EXCLUDED.steps, kcal = EXCLUDED.kcal, meters = EXCLUDED.meters,
               sleep_min = EXCLUDED.sleep_min, deep_sleep_min = EXCLUDED.deep_sleep_min,
               light_sleep_min = EXCLUDED.light_sleep_min,
               -- A value the watch did not measure this time must not erase the
               -- one it measured an hour ago: COALESCE keeps the last real
               -- reading rather than writing the day back to "never measured".
               stress = COALESCE(EXCLUDED.stress, wearable_days.stress),
               breath_rate = COALESCE(EXCLUDED.breath_rate, wearable_days.breath_rate),
               met = COALESCE(EXCLUDED.met, wearable_days.met),
               battery_pct = COALESCE(EXCLUDED.battery_pct, wearable_days.battery_pct),
               charging = EXCLUDED.charging, worn = EXCLUDED.worn,
               -- Same rule for the history vitals. This is what makes re-running
               -- the backfill safe: the second sync of a day updates the row it
               -- already wrote, and a metric the newer read did not carry keeps
               -- the value the older one found instead of being blanked.
               hr_avg  = COALESCE(EXCLUDED.hr_avg,  wearable_days.hr_avg),
               hr_min  = COALESCE(EXCLUDED.hr_min,  wearable_days.hr_min),
               hr_max  = COALESCE(EXCLUDED.hr_max,  wearable_days.hr_max),
               spo2_avg = COALESCE(EXCLUDED.spo2_avg, wearable_days.spo2_avg),
               spo2_min = COALESCE(EXCLUDED.spo2_min, wearable_days.spo2_min),
               systolic_avg  = COALESCE(EXCLUDED.systolic_avg,  wearable_days.systolic_avg),
               diastolic_avg = COALESCE(EXCLUDED.diastolic_avg, wearable_days.diastolic_avg),
               temp_avg_tenths = COALESCE(EXCLUDED.temp_avg_tenths, wearable_days.temp_avg_tenths),
               blood_sugar_tenths =
                 COALESCE(EXCLUDED.blood_sugar_tenths, wearable_days.blood_sugar_tenths)`,
        [row.userId, row.deviceId, row.day, row.recordedAt, row.steps, row.kcal, row.meters,
         row.sleepMinutes, row.deepSleepMinutes, row.lightSleepMinutes,
         row.stress ?? null, row.breathRate ?? null, row.met ?? null,
         row.batteryPercent ?? null, row.charging, row.worn,
         row.heartRateAvg ?? null, row.heartRateMin ?? null, row.heartRateMax ?? null,
         row.spo2Avg ?? null, row.spo2Min ?? null,
         row.systolicAvg ?? null, row.diastolicAvg ?? null,
         row.tempAvgTenths ?? null, row.bloodSugarTenths ?? null]);
    },
    async listWearableDays(userId, limit) {
      // The MAC comes back, not our UUID: WearableDayRow.deviceId is the
      // physical identifier everywhere else it appears — in the ingest
      // payload, in the app, and on the back of the watch a support call is
      // asking about.
      const { rows } = await pool.query(
        `SELECT d.ble_mac AS device_id, w.day, w.recorded_at, w.steps, w.kcal, w.meters,
                w.sleep_min, w.deep_sleep_min, w.light_sleep_min,
                w.stress, w.breath_rate, w.met, w.battery_pct, w.charging, w.worn,
                w.hr_avg, w.hr_min, w.hr_max, w.spo2_avg, w.spo2_min,
                w.systolic_avg, w.diastolic_avg, w.temp_avg_tenths, w.blood_sugar_tenths
           FROM wearable_days w
           JOIN devices d ON d.id = w.device_id
          WHERE w.user_id = $1 ORDER BY w.day DESC LIMIT $2`,
        [userId, limit]);
      return rows.map((r) => ({
        deviceId: r.device_id,
        day: new Date(r.day).toISOString().slice(0, 10),
        recordedAt: new Date(r.recorded_at).toISOString(),
        steps: r.steps, kcal: r.kcal, meters: r.meters,
        sleepMinutes: r.sleep_min,
        deepSleepMinutes: r.deep_sleep_min,
        lightSleepMinutes: r.light_sleep_min,
        stress: r.stress, breathRate: r.breath_rate, met: r.met,
        batteryPercent: r.battery_pct,
        charging: r.charging, worn: r.worn,
        // Selected AND returned. A column the query reads and the mapper drops
        // is the same defect as never storing it: the clinician's view would
        // show a day of walking with no heart rate in it.
        heartRateAvg: r.hr_avg, heartRateMin: r.hr_min, heartRateMax: r.hr_max,
        spo2Avg: r.spo2_avg, spo2Min: r.spo2_min,
        systolicAvg: r.systolic_avg, diastolicAvg: r.diastolic_avg,
        tempAvgTenths: r.temp_avg_tenths, bloodSugarTenths: r.blood_sugar_tenths,
      }));
    },

    // ---- Baby cry-analysis history ----
    async recordCry(userId, c) {
      // The verdict is NOT in the SET list on purpose. The app re-pushes its
      // whole cry history on every sign-in, and overwriting the row wholesale
      // would erase «это было верно?» — the only ground truth this product has
      // — every time a mother reinstalls the app.
      await pool.query(
        `INSERT INTO cry_results (user_id, at, reason, confidence)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (user_id, at) DO UPDATE
           SET reason = EXCLUDED.reason, confidence = EXCLUDED.confidence`,
        [userId, c.at, c.reason, c.confidence]);
    },
    async listCry(userId, limit) {
      const { rows } = await pool.query(
        `SELECT at, reason, confidence, verdict, actual_reason FROM cry_results
         WHERE user_id = $1 ORDER BY at DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({
        at: new Date(r.at).toISOString(), reason: r.reason, confidence: Number(r.confidence),
        verdict: r.verdict ?? null, actualReason: r.actual_reason ?? null,
      }));
    },
    // «Это было верно?» — frame 17c. Scoped to HER analyses by user_id: a
    // verdict is a statement about one mother's own recording, and keying it by
    // the instant alone would let one account rate another's.
    async recordCryVerdict(userId, at, verdict, actualReason) {
      const { rowCount } = await pool.query(
        `UPDATE cry_results SET verdict = $3, actual_reason = $4
          WHERE user_id = $1 AND at = $2`,
        [userId, at, verdict, actualReason]);
      return (rowCount ?? 0) > 0;
    },
    /**
     * The detector's aggregate picture — every user, no user named.
     *
     * `belowThreshold` is counted against the threshold IN FORCE, read in the
     * same statement rather than passed in, so the panel cannot report "how
     * many were suppressed" against a number that is no longer the one the app
     * applies. An absent settings row means the shipped default.
     */
    async cryStats(days) {
      const { rows } = await pool.query(
        `WITH t AS (
           SELECT COALESCE((SELECT min_confidence FROM cry_settings WHERE id), $2::real) AS min_confidence
         )
         SELECT reason,
                COUNT(*)::int                                          AS count,
                AVG(confidence)::float8                                AS avg_confidence,
                COUNT(*) FILTER (WHERE confidence < t.min_confidence)::int AS below_threshold,
                COUNT(*) FILTER (WHERE verdict = 'correct')::int        AS correct,
                COUNT(*) FILTER (WHERE verdict = 'wrong')::int          AS wrong,
                COUNT(*) FILTER (WHERE verdict IS NULL)::int            AS unrated,
                MAX(at)                                                AS last_at,
                MIN(at)                                                AS first_at
           FROM cry_results, t
          WHERE at >= now() - ($1::int * INTERVAL '1 day')
          GROUP BY reason, t.min_confidence
          ORDER BY count DESC, reason ASC`,
        [days, CRY_MIN_CONFIDENCE_DEFAULT]);
      const byReason = rows.map((r) => ({
        reason: r.reason,
        count: Number(r.count),
        avgConfidence: Number(r.avg_confidence),
        belowThreshold: Number(r.below_threshold),
        correct: Number(r.correct),
        wrong: Number(r.wrong),
      }));
      // The window's edges across ALL reasons: the GROUP BY gives one pair per
      // reason, and «последний разбор» is about the detector, not about hunger.
      const stamps = (col: 'last_at' | 'first_at') => rows
        .map((r) => (r[col] ? new Date(r[col]).toISOString() : null))
        .filter((x): x is string => x !== null)
        .sort();
      return {
        analyses: byReason.reduce((n, r) => n + r.count, 0),
        byReason,
        unrated: rows.reduce((n, r) => n + Number(r.unrated), 0),
        lastAt: stamps('last_at').pop() ?? null,
        firstAt: stamps('first_at').shift() ?? null,
      };
    },
    async getCryThreshold() {
      const { rows } = await pool.query(
        `SELECT min_confidence, updated_at, updated_by FROM cry_settings WHERE id`);
      const r = rows[0];
      if (!r) return null; // nobody has chosen — the shipped default is in force
      return {
        minConfidence: Number(r.min_confidence),
        updatedAt: new Date(r.updated_at).toISOString(),
        updatedBy: r.updated_by ?? null,
      };
    },
    async setCryThreshold(v) {
      await pool.query(
        `INSERT INTO cry_settings (id, min_confidence, updated_at, updated_by)
         VALUES (TRUE, $1, now(), $2)
         ON CONFLICT (id) DO UPDATE
           SET min_confidence = EXCLUDED.min_confidence,
               updated_at = now(),
               updated_by = EXCLUDED.updated_by`,
        [v.minConfidence, v.updatedBy]);
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

    // ---- Postpartum screening (EPDS) ----
    //
    // Four columns, and the fifth one does not exist: the ten answers are never
    // sent and there is nowhere here to put them. See migration 049.
    async upsertEpds(userId, row) {
      await pool.query(
        `INSERT INTO epds_results (user_id, id, taken_at, score, band)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (user_id, id) DO UPDATE
           SET taken_at = EXCLUDED.taken_at, score = EXCLUDED.score, band = EXCLUDED.band`,
        [userId, row.id, row.takenAt, row.score, row.band]);
    },
    async listEpds(userId, limit) {
      const { rows } = await pool.query(
        `SELECT id, taken_at, score, band FROM epds_results
         WHERE user_id = $1 ORDER BY taken_at DESC LIMIT $2`, [userId, limit]);
      return rows.map((r) => ({
        id: r.id, takenAt: new Date(r.taken_at).toISOString(), score: r.score, band: r.band,
      }));
    },

    // ---- Safety alerts ----
    // ---- Support (frame 12) ----
    async listSupportTickets(limit) {
      const { rows } = await pool.query(
        `SELECT ${SUPPORT_COLS} ${SUPPORT_FROM}
          ORDER BY t.created_at DESC LIMIT $1`, [limit]);
      return rows.map(supportRow);
    },
    async listSupportTicketsForUser(userId, limit) {
      // By user_id ONLY. See the interface: matching on the phone would hand
      // one person's support conversation to whoever signs in with that number
      // next, and tickets with no account are exactly the ones most likely to
      // carry somebody else's number.
      const { rows } = await pool.query(
        `SELECT ${SUPPORT_COLS} ${SUPPORT_FROM}
          WHERE t.user_id = $1 ORDER BY t.created_at DESC LIMIT $2`, [userId, limit]);
      return rows.map(supportRow);
    },
    async getSupportTicket(id) {
      const { rows } = await pool.query(
        `SELECT ${SUPPORT_COLS} ${SUPPORT_FROM} WHERE t.id = $1`, [id]);
      return rows[0] ? supportRow(rows[0]) : null;
    },
    async createSupportTicket(t) {
      const { rows } = await pool.query(
        `INSERT INTO support_tickets
           (user_id, phone, customer_name, channel, subject, body, app_context)
         VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
        [t.userId ?? null, t.phone ?? null, t.customerName ?? null,
         t.channel ?? 'whatsapp', t.subject, t.body ?? '', t.appContext ?? null]);
      return rows[0].id;
    },
    async updateSupportTicket(id, patch) {
      // Built from the keys PRESENT, so closing a ticket does not clear its
      // assignee and assigning one does not reopen it.
      const cols: Record<string, string> = {
        status: 'status', assigneeId: 'assignee_id',
        answeredAt: 'answered_at', closedAt: 'closed_at',
      };
      const sets: string[] = [];
      const vals: unknown[] = [];
      for (const [key, col] of Object.entries(cols)) {
        if (!Object.prototype.hasOwnProperty.call(patch, key)) continue;
        vals.push((patch as Record<string, unknown>)[key]);
        sets.push(`${col} = $${vals.length}`);
      }
      if (!sets.length) return false;
      // Always bumped: the board sorts on it, and an edit that leaves it stale
      // puts the ticket back where it was.
      sets.push('updated_at = now()');
      vals.push(id);
      const { rowCount } = await pool.query(
        `UPDATE support_tickets SET ${sets.join(', ')} WHERE id = $${vals.length}`, vals);
      return (rowCount ?? 0) > 0;
    },
    async listSupportReplies(ticketId) {
      const { rows } = await pool.query(
        `SELECT id, ticket_id, author, staff_id, body, at
           FROM support_replies WHERE ticket_id = $1 ORDER BY at`, [ticketId]);
      return rows.map((r) => ({
        id: r.id, ticketId: r.ticket_id, author: r.author, staffId: r.staff_id,
        body: r.body, at: new Date(r.at).toISOString(),
      }));
    },
    async addSupportReply(r) {
      await pool.query(
        `INSERT INTO support_replies (ticket_id, author, staff_id, body)
         VALUES ($1,$2,$3,$4)`,
        [r.ticketId, r.author, r.staffId ?? null, r.body]);
    },
    async markSupportTicketRead(id, at) {
      // customer_read_at ONLY — not status, not updated_at. See the interface:
      // her reading a thread must not move the ticket in the operator's queue.
      const { rowCount } = await pool.query(
        'UPDATE support_tickets SET customer_read_at = $2 WHERE id = $1', [id, at]);
      return (rowCount ?? 0) > 0;
    },
    async listSupportTemplates() {
      const { rows } = await pool.query(
        'SELECT id, title, body_ru, body_kk, sort FROM support_templates ORDER BY sort, title');
      return rows.map((r) => ({
        id: r.id, title: r.title, bodyRu: r.body_ru, bodyKk: r.body_kk, sort: r.sort,
      }));
    },

    async recordAlert(userId, a) {
      await pool.query(
        `INSERT INTO safety_alerts (user_id, child_id, kind, zone_name, at) VALUES ($1,$2,$3,$4,$5)`,
        [userId, a.childId, a.kind, a.zoneName, a.at]);
    },
    async listAlerts(userId, limit, fromIso, toIso) {
      // Positional params built up, not hard-coded: two optional bounds with
      // fixed $3/$4 is how one ends up reading the other one's value.
      // idx_safety_alerts_user_at (user_id, at DESC) serves this as it stands.
      const params: unknown[] = [userId, limit];
      const where: string[] = ['user_id = $1'];
      if (fromIso) { params.push(fromIso); where.push(`at >= $${params.length}`); }
      if (toIso) { params.push(toIso); where.push(`at < $${params.length}`); }
      const { rows } = await pool.query(
        `SELECT child_id, kind, zone_name, at, outcome FROM safety_alerts
         WHERE ${where.join(' AND ')} ORDER BY at DESC LIMIT $2`, params);
      return rows.map((r) => ({
        childId: r.child_id, kind: r.kind, zoneName: r.zone_name, at: new Date(r.at).toISOString(),
        outcome: r.outcome ?? null,
      }));
    },
    async setAlertOutcome(userId, childId, at, outcome) {
      // Scoped by user_id as well as child: the caller's access to the child was
      // already checked, but a write that trusts only the path parameter is one
      // bad guard away from closing somebody else's alarm.
      //
      // The instant is matched as a timestamp rather than a string so the two
      // representations of the same moment — the ISO form the client echoes back
      // and whatever precision the column holds — compare equal.
      const { rowCount } = await pool.query(
        `UPDATE safety_alerts SET outcome = $4
         WHERE user_id = $1 AND child_id = $2 AND at = $3::timestamptz AND kind = 'sos'`,
        [userId, childId, at, outcome]);
      return (rowCount ?? 0) > 0;
    },

    // ---- Profile ----
    async getProfile(userId) {
      const { rows } = await pool.query(
        `SELECT display_name, phone_e164, due_date, locale, birth_date, city, address,
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
        // Screen 37's dispatcher card. Null survives as null: an empty string
        // would make the screen print a blank address card instead of the
        // «Добавьте адрес» prompt that tells her to fix it.
        address: r.address ?? null,
        doctorPhone: r.doctor_phone ?? null,
        avgCycleLength: r.avg_cycle_length === null ? null : Number(r.avg_cycle_length),
        avgPeriodLength: r.avg_period_length === null ? null : Number(r.avg_period_length),
      };
    },
    async upsertProfile(userId, p) {
      // The user row exists from sign-in (the phone created it); this updates it.
      //
      // `phone_e164` is NOT in this statement and must never be. It is the
      // column POST /auth/phone resolves an account by, so writing it here let
      // a signed-in user claim a number that was not hers and inherit whoever
      // later signed in with it. `doctor_phone` below is a different thing
      // entirely — a number she calls, never one she is identified by.
      await pool.query(
        `UPDATE users SET display_name = $2, due_date = $3,
                          locale = COALESCE($4, locale),
                          birth_date = $5, city = $6, address = $7, doctor_phone = $8,
                          avg_cycle_length = $9, avg_period_length = $10, updated_at = now()
         WHERE id = $1`,
        [userId, p.displayName, p.dueDate, p.locale, p.birthDate, p.city, p.address,
         p.doctorPhone, p.avgCycleLength, p.avgPeriodLength]);
    },

    // ---- Device reassignment ----
    async reassignDevice(deviceId, childId) {
      await pool.query(`UPDATE devices SET child_id = $2 WHERE ble_mac = $1`, [deviceId, childId]);
    },

    // ---- Shop ----
    async shopProducts() {
      // The catalogue columns (migration 033) travel with the product. Without
      // them /shop/products answered with five fields and the app hard-coded
      // the rest, so an operator's price, Kazakh name, stage and age band
      // reached the panel and stopped there.
      const { rows } = await pool.query(
        `SELECT p.id, p.name, p.price_minor, COALESCE(p.kind, 'simple') AS kind,
                p.name_kk, p.description_ru, p.description_kk,
                p.stage, p.category, p.age_min_months, p.age_max_months, p.photo_url,
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
          p = {
            id: r.id, name: r.name, priceMinor: r.price_minor, variants: [], kind: r.kind, parts: [],
            nameKk: r.name_kk ?? null,
            descriptionRu: r.description_ru ?? null,
            descriptionKk: r.description_kk ?? null,
            stage: r.stage ?? null,
            category: r.category ?? null,
            ageMinMonths: r.age_min_months === null || r.age_min_months === undefined ? null : Number(r.age_min_months),
            ageMaxMonths: r.age_max_months === null || r.age_max_months === undefined ? null : Number(r.age_max_months),
            photoUrl: r.photo_url ?? null,
            inStock: false,
          };
          byId.set(r.id, p);
        }
        if (r.vid) p.variants.push({ id: r.vid, color: r.color, colorHex: r.color_hex, stock: r.stock });
      }
      for (const r of partRows) byId.get(r.bundle_id)?.parts.push({ partId: r.part_id, qty: r.qty });
      // A bundle's parts may themselves be inactive and therefore absent from
      // `byId`; markInStock treats an unresolvable part as unavailable, which
      // is right — the set cannot be assembled.
      return markInStock([...byId.values()]);
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
    // ---- Catalogue (frames 08 / 08a / 08b) ----
    async updateProduct(id, patch) {
      // Built from the keys PRESENT, so saving one tab cannot blank another.
      const cols: Record<string, string> = {
        name: 'name', nameKk: 'name_kk', priceMinor: 'price_minor',
        costMinor: 'cost_minor', active: 'active', sort: 'sort', sku: 'sku',
        category: 'category', stage: 'stage',
        descriptionRu: 'description_ru', descriptionKk: 'description_kk',
        ageMinMonths: 'age_min_months', ageMaxMonths: 'age_max_months',
        photoUrl: 'photo_url', seoSlug: 'seo_slug', seoTitle: 'seo_title',
        seoDescription: 'seo_description',
      };
      const sets: string[] = [];
      const vals: unknown[] = [];
      for (const [key, col] of Object.entries(cols)) {
        if (!Object.prototype.hasOwnProperty.call(patch, key)) continue;
        vals.push((patch as Record<string, unknown>)[key]);
        sets.push(`${col} = $${vals.length}`);
      }
      if (!sets.length) return; // nothing asked for is not an error
      vals.push(id);
      await pool.query(
        `UPDATE shop_products SET ${sets.join(', ')} WHERE id = $${vals.length}`, vals);
    },
    async listShopCategories() {
      const { rows } = await pool.query(
        'SELECT id, name_ru, name_kk, sort FROM shop_categories ORDER BY sort, name_ru');
      return rows.map((r) => ({ id: r.id, nameRu: r.name_ru, nameKk: r.name_kk, sort: r.sort }));
    },
    async upsertShopCategory(c) {
      await pool.query(
        `INSERT INTO shop_categories (id, name_ru, name_kk, sort) VALUES ($1,$2,$3,$4)
         ON CONFLICT (id) DO UPDATE SET name_ru = $2, name_kk = $3, sort = $4`,
        [c.id, c.nameRu, c.nameKk, c.sort]);
    },
    async deleteShopCategory(id) {
      // Refused while anything still points at it. The FK is ON DELETE SET
      // NULL, so this would otherwise succeed and quietly uncategorise a shelf.
      const { rows } = await pool.query(
        'SELECT 1 FROM shop_products WHERE category = $1 LIMIT 1', [id]);
      if (rows[0]) return false;
      await pool.query('DELETE FROM shop_categories WHERE id = $1', [id]);
      return true;
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

    async courseLessonWatchers(lessonId) {
      const { rows } = await pool.query(
        'SELECT count(*)::int AS n FROM course_progress WHERE lesson_id = $1', [lessonId]);
      return Number(rows[0]?.n ?? 0);
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
                p.name_kk, p.stage, p.category, p.description_ru, p.description_kk,
                p.age_min_months, p.age_max_months, p.photo_url,
                p.seo_slug, p.seo_title, p.seo_description,
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
            nameKk: r.name_kk ?? null, stage: r.stage ?? null, category: r.category ?? null,
            descriptionRu: r.description_ru ?? null, descriptionKk: r.description_kk ?? null,
            ageMinMonths: r.age_min_months ?? null, ageMaxMonths: r.age_max_months ?? null,
            photoUrl: r.photo_url ?? null,
            seoSlug: r.seo_slug ?? null, seoTitle: r.seo_title ?? null,
            seoDescription: r.seo_description ?? null,
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

    async soldUnitsSince(sinceIso) {
      const { rows } = await pool.query(
        `SELECT v.product_id AS id, -SUM(m.delta)::int AS sold
           FROM shop_stock_moves m
           JOIN shop_variants v ON v.id = m.variant_id
          WHERE m.reason = 'sale' AND m.at >= $1
          GROUP BY v.product_id`,
        [sinceIso]);
      const out: Record<string, number> = {};
      // A 'sale' row is negative, so the negated sum is positive. Clamped
      // anyway: a correction miskeyed as a sale could make it negative, and a
      // negative sales rate would report a shelf that fills itself.
      for (const r of rows) out[r.id] = Math.max(0, Number(r.sold) || 0);
      return out;
    },

    async stockMoves(limit, variantId, sinceIso) {
      // Built up rather than interpolated: two optional conditions with hard
      // -coded $2/$3 is how a filter ends up reading the other one's value.
      const params: unknown[] = [limit];
      const where: string[] = [];
      if (variantId) { params.push(variantId); where.push(`m.variant_id = $${params.length}`); }
      // Inclusive, matching the memory repository — a move booked exactly at
      // midnight belongs to the day that is starting.
      if (sinceIso) { params.push(sinceIso); where.push(`m.at >= $${params.length}`); }
      const { rows } = await pool.query(
        `SELECT m.id, m.variant_id, m.delta, m.reason, m.note, m.staff_id, m.order_id, m.at,
                v.color, p.name AS product_name
           FROM shop_stock_moves m
           JOIN shop_variants v ON v.id = m.variant_id
           JOIN shop_products p ON p.id = v.product_id
          ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
          ORDER BY m.at DESC, m.id DESC
          LIMIT $1`,
        params);
      return rows.map((r) => ({
        id: Number(r.id), variantId: r.variant_id, productName: r.product_name,
        color: r.color, delta: r.delta, reason: r.reason, note: r.note,
        staffId: r.staff_id, orderId: r.order_id,
        at: new Date(r.at).toISOString(),
      }));
    },
    // ---- Поставки (migration 045, frames 07a / 07g) ----
    async listSuppliers() {
      const { rows } = await pool.query(
        `SELECT id, name, contact, lead_time_days, active, created_at
           FROM suppliers
          ORDER BY active DESC, lower(name)`);
      return rows.map((r) => ({
        id: r.id, name: r.name, contact: r.contact,
        leadTimeDays: r.lead_time_days == null ? null : Number(r.lead_time_days),
        active: r.active, createdAt: new Date(r.created_at).toISOString(),
      }));
    },

    async upsertSupplier(s) {
      const name = s.name.trim();
      if (s.id) {
        try {
          const { rows } = await pool.query(
            `UPDATE suppliers
                SET name = $2, contact = $3, lead_time_days = $4, active = COALESCE($5, active)
              WHERE id = $1
          RETURNING id`,
            [s.id, name, s.contact ?? null, s.leadTimeDays ?? null, s.active ?? null]);
          if (rows[0]) return { ok: true as const, id: rows[0].id };
        } catch (e) {
          // 23505 = the UNIQUE lower(name) index. Renaming Alpha to Beta is a
          // refusal with a reason, and letting it escape gave the operator a
          // 500 and the panel a generic «не удалось» with no mention of the name.
          if ((e as { code?: string }).code === '23505') {
            return { ok: false as const, error: 'name_taken' as const };
          }
          throw e;
        }
      }
      // ON CONFLICT on the UNIQUE lower(name) index: adding a supplier that is
      // already there is an edit, not an error somebody has to interpret.
      //
      // `active` is COALESCEd rather than taken from EXCLUDED: the panel's add
      // form sends no `active`, and `EXCLUDED.active` defaulted to true, so
      // retyping an archived supplier's name silently un-archived them and put
      // them back in the «Заказ поставщику» dropdown. Absent means "leave it".
      const { rows } = await pool.query(
        `INSERT INTO suppliers (name, contact, lead_time_days, active)
         VALUES ($1,$2,$3, COALESCE($4::boolean, true))
         ON CONFLICT (lower(name)) DO UPDATE SET
           contact = EXCLUDED.contact,
           lead_time_days = EXCLUDED.lead_time_days,
           active = COALESCE($4::boolean, suppliers.active)
         RETURNING id`,
        [name, s.contact ?? null, s.leadTimeDays ?? null, s.active ?? null]);
      return { ok: true as const, id: rows[0].id };
    },

    async listPurchaseOrders(limit) {
      const { rows } = await pool.query(
        `SELECT o.id, o.supplier_id, o.status, o.placed_at, o.expected_at, o.note,
                o.created_by, o.created_at, o.updated_at,
                s.name AS supplier_name, s.lead_time_days AS supplier_lead_time_days
           FROM purchase_orders o
           LEFT JOIN suppliers s ON s.id = o.supplier_id
          ORDER BY o.created_at DESC
          LIMIT $1`, [limit]);
      if (!rows.length) return [];
      // One read for every line of every order on the page, rather than a query
      // per order: the list is drawn on every render of the warehouse screen.
      const { rows: items } = await pool.query(
        `SELECT i.po_id, i.variant_id, i.qty_ordered, i.unit_cost_minor,
                i.qty_received, i.received_at,
                v.product_id, v.color, p.name AS product_name
           FROM purchase_order_items i
           JOIN shop_variants v ON v.id = i.variant_id
           JOIN shop_products p ON p.id = v.product_id
          WHERE i.po_id = ANY($1::uuid[])
          ORDER BY p.sort, p.name, v.sort, v.color`,
        [rows.map((r) => r.id)]);
      return rows.map((r) => purchaseOrderFromRows(r, items.filter((i) => i.po_id === r.id)));
    },

    async purchaseOrderById(id) {
      const { rows } = await pool.query(
        `SELECT o.id, o.supplier_id, o.status, o.placed_at, o.expected_at, o.note,
                o.created_by, o.created_at, o.updated_at,
                s.name AS supplier_name, s.lead_time_days AS supplier_lead_time_days
           FROM purchase_orders o
           LEFT JOIN suppliers s ON s.id = o.supplier_id
          WHERE o.id = $1`, [id]);
      if (!rows[0]) return null;
      const { rows: items } = await pool.query(
        `SELECT i.po_id, i.variant_id, i.qty_ordered, i.unit_cost_minor,
                i.qty_received, i.received_at,
                v.product_id, v.color, p.name AS product_name
           FROM purchase_order_items i
           JOIN shop_variants v ON v.id = i.variant_id
           JOIN shop_products p ON p.id = v.product_id
          WHERE i.po_id = $1
          ORDER BY p.sort, p.name, v.sort, v.color`, [id]);
      return purchaseOrderFromRows(rows[0], items);
    },

    async createPurchaseOrder(po) {
      if (!po.items.length) return { ok: false as const, error: 'no_items' as const };
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        // Checked inside the transaction, so an order cannot be written half
        // valid: the foreign key would refuse the line anyway, and this turns
        // that into an answer the panel can print.
        const { rows: known } = await client.query(
          'SELECT id FROM shop_variants WHERE id = ANY($1::uuid[])',
          [po.items.map((i) => i.variantId)]);
        const ids = new Set(known.map((r) => r.id));
        if (po.items.some((i) => !ids.has(i.variantId))) {
          await client.query('ROLLBACK');
          return { ok: false as const, error: 'unknown_variant' as const };
        }
        const { rows } = await client.query(
          `INSERT INTO purchase_orders (supplier_id, status, expected_at, note, created_by)
           VALUES ($1,'draft',$2,$3,$4) RETURNING id`,
          [po.supplierId ?? null, po.expectedAt ?? null, po.note ?? null, po.createdBy ?? null]);
        const id = rows[0].id;
        for (const it of po.items) {
          // The same colour twice in one order is one line, summed — the
          // primary key would refuse a second row.
          await client.query(
            `INSERT INTO purchase_order_items (po_id, variant_id, qty_ordered, unit_cost_minor)
             VALUES ($1,$2,$3,$4)
             ON CONFLICT (po_id, variant_id) DO UPDATE SET
               qty_ordered = purchase_order_items.qty_ordered + EXCLUDED.qty_ordered`,
            [id, it.variantId, Math.trunc(it.qtyOrdered), it.unitCostMinor ?? null]);
        }
        await client.query('COMMIT');
        return { ok: true as const, id };
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },

    async setPurchaseOrderStatus(id, status) {
      const { rowCount } = await pool.query(
        `UPDATE purchase_orders
            SET status = $2,
                placed_at = CASE WHEN $2 = 'placed' AND placed_at IS NULL THEN now() ELSE placed_at END,
                updated_at = now()
          WHERE id = $1`, [id, status]);
      return (rowCount ?? 0) > 0;
    },

    async receivePurchaseOrderLine(poId, variantId, qtyReceived) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const { rows } = await client.query(
          `UPDATE purchase_order_items
              SET qty_received = qty_received + $3, received_at = now()
            WHERE po_id = $1 AND variant_id = $2
        RETURNING qty_ordered`,
          [poId, variantId, Math.max(0, Math.trunc(qtyReceived))]);
        if (!rows[0]) {
          await client.query('ROLLBACK');
          return { ok: false, status: null, qtyOrdered: null };
        }
        // Closed even when short: the shortfall is already a claim recorded on
        // the receipt, and an order held open over two missing units would show
        // them as "in transit" for ever.
        const { rows: statusRows } = await client.query(
          `UPDATE purchase_orders o
              SET status = CASE
                    WHEN o.status = 'cancelled' THEN o.status
                    WHEN NOT EXISTS (
                      SELECT 1 FROM purchase_order_items i
                       WHERE i.po_id = o.id AND i.received_at IS NULL
                    ) THEN 'received'
                    ELSE o.status END,
                  updated_at = now()
            WHERE o.id = $1
        RETURNING o.status`, [poId]);
        await client.query('COMMIT');
        return {
          ok: true,
          status: (statusRows[0]?.status ?? null) as PurchaseOrderStatus | null,
          qtyOrdered: Number(rows[0].qty_ordered),
        };
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    },

    async inTransitByVariant() {
      // Only PLACED orders, and only lines a receipt has not closed. A draft is
      // not on the water and a cancelled order never will be.
      const { rows } = await pool.query(
        `SELECT i.variant_id, SUM(i.qty_ordered)::int AS qty
           FROM purchase_order_items i
           JOIN purchase_orders o ON o.id = i.po_id
          WHERE o.status = 'placed' AND i.received_at IS NULL
          GROUP BY i.variant_id`);
      const out: Record<string, number> = {};
      for (const r of rows) out[r.variant_id] = Math.max(0, Number(r.qty) || 0);
      return out;
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
    async shopOrdersByPhone(phone, limit) {
      // Same shape as adminShopOrders, filtered to one customer. Kept as its
      // own query rather than fetching everything and filtering in Node: this
      // is a customer-facing read, and pulling every order in the shop to
      // answer it would leak nothing but would scale terribly and log badly.
      //
      // Matched on phone_normalized, NOT on `phone`. The raw column holds what
      // the customer typed — «+7 (707) 345-22-44», «8 707 345 22 44» — and the
      // normalised one exists precisely because those are one number. Matching
      // on the raw form would show an empty screen to a woman with a charge on
      // her card, which is the class of bug src/phone.ts was written to end.
      const { rows } = await pool.query(
        `SELECT id, customer_name, phone, city, address, note, total_minor,
                discount_minor, status, created_at
           FROM shop_orders
          WHERE phone_normalized = $1
          ORDER BY created_at DESC
          LIMIT $2`,
        [phone, limit],
      );
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

    async adminShopOrderPage({ limit, offset, status }) {
      // Two reads, on purpose. `total` has to follow the filter — «Показано 25
      // из 40 отменённых» — while `counts` must NOT, because those numbers are
      // printed on the filter chips themselves and a counter that changed when
      // you clicked it tells the operator nothing.
      const where = status ? 'WHERE status = $3' : '';
      const params: unknown[] = status ? [limit, offset, status] : [limit, offset];
      const { rows } = await pool.query(
        `SELECT id, customer_name, phone, city, address, note, total_minor,
                discount_minor, status, created_at,
                COUNT(*) OVER() AS match_total
           FROM shop_orders ${where}
          ORDER BY created_at DESC
          LIMIT $1 OFFSET $2`,
        params,
      );
      const { rows: tally } = await pool.query(
        'SELECT status, COUNT(*)::int AS n FROM shop_orders GROUP BY status');
      const counts: Record<ShopOrderStatus, number> = {
        new: 0, confirmed: 0, shipped: 0, delivered: 0, cancelled: 0,
      };
      for (const t of tally) counts[t.status as ShopOrderStatus] = Number(t.n);

      // An empty page is not the same as an empty table: page 3 of a two-page
      // list has no rows and a real total, so the total comes from the tally
      // when the window function had no row to hang it on.
      const total = rows.length
        ? Number(rows[0].match_total)
        : status
          ? counts[status]
          : Object.values(counts).reduce((a, b) => a + b, 0);
      if (!rows.length) return { orders: [], total, counts };

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
      return {
        orders: rows.map((r) => ({
          id: r.id, customerName: r.customer_name, phone: r.phone, city: r.city, address: r.address,
          note: r.note, totalMinor: r.total_minor, discountMinor: r.discount_minor, status: r.status,
          createdAt: new Date(r.created_at).toISOString(), items: byOrder.get(r.id) ?? [],
        })),
        total,
        counts,
      };
    },

    async shopOrderById(id) {
      // Guarded like every other UUID lookup: shop_orders.id is a uuid column,
      // so `/admin/shop/orders/order-1` would raise 22P02 and answer 500 where
      // the truth is «такого заказа нет».
      if (!looksLikeUuid(id)) return null;
      const { rows } = await pool.query(
        `SELECT id, customer_name, phone, city, address, note, total_minor,
                discount_minor, status, created_at
           FROM shop_orders WHERE id = $1`, [id]);
      if (!rows[0]) return null;
      const { rows: items } = await pool.query(
        `SELECT product_name, color, qty, unit_price_minor
           FROM shop_order_items WHERE order_id = $1`, [id]);
      const r = rows[0];
      return {
        id: r.id, customerName: r.customer_name, phone: r.phone, city: r.city, address: r.address,
        note: r.note, totalMinor: r.total_minor, discountMinor: r.discount_minor, status: r.status,
        createdAt: new Date(r.created_at).toISOString(),
        items: items.map((i) => ({
          productName: i.product_name, color: i.color, qty: i.qty, unitPriceMinor: i.unit_price_minor,
        })),
      };
    },

    async shopOrderEvents(orderId) {
      if (!looksLikeUuid(orderId)) return [];
      // LEFT JOIN and the id is kept, exactly like listAudit: a transition made
      // by an account since removed must stay on the timeline.
      const { rows } = await pool.query(
        `SELECT e.id, e.order_id, e.from_status, e.to_status, e.staff_id, e.at,
                a.display_name AS staff_name
           FROM shop_order_events e
           LEFT JOIN staff_accounts a ON a.id::text = e.staff_id
          WHERE e.order_id = $1
          ORDER BY e.at ASC, e.id ASC`,
        [orderId],
      );
      return rows.map((r) => ({
        id: Number(r.id),
        orderId: r.order_id,
        fromStatus: r.from_status ?? null,
        toStatus: r.to_status,
        staffId: r.staff_id ?? null,
        staffName: r.staff_name ?? null,
        at: new Date(r.at).toISOString(),
      }));
    },

    async setShopOrderStatus(orderId, status, staffId) {
      // Cancelling puts the goods back on the shelf.
      //
      // It did not, before: the order was marked cancelled and the stock stayed
      // gone, so every cancellation quietly shrank the sellable inventory until
      // somebody noticed the shop was "out" of something sitting in the room.
      //
      // Same reason as shopOrderById: an id that cannot be a UUID is an order
      // we do not have, not a 500.
      if (!looksLikeUuid(orderId)) return;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const { rows: prev } = await client.query(
          'SELECT status FROM shop_orders WHERE id = $1 FOR UPDATE', [orderId]);
        if (!prev[0]) { await client.query('ROLLBACK'); return; }
        const was = prev[0].status as string;
        await client.query('UPDATE shop_orders SET status = $2 WHERE id = $1', [orderId, status]);

        // The timeline row, inside the same transaction as the move it
        // describes. A history written afterwards, outside the lock, is a
        // history that disagrees with the order it belongs to the first time
        // anything fails between the two statements.
        //
        // Only on a REAL transition: re-selecting the status a row already has
        // would otherwise fill frame 03 with «Отправлен → Отправлен».
        if (was !== status) {
          await client.query(
            `INSERT INTO shop_order_events (order_id, from_status, to_status, staff_id)
             VALUES ($1,$2,$3,$4)`,
            [orderId, was, status, staffId ?? null]);
        }

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
    /**
     * The whole table, in one round trip — deliberately the SAME expression the
     * dashboard's `leads` block uses twenty lines into adminDashboard. Two
     * queries counting one queue is how «не обработано: 12» and «50 из 140»
     * come to stand on the same screen.
     */
    async shopLeadCounts() {
      const { rows } = await pool.query(
        `SELECT count(*) AS total, count(*) FILTER (WHERE status = 'new') AS uncalled
           FROM shop_leads`);
      return { total: Number(rows[0]?.total ?? 0), uncalled: Number(rows[0]?.uncalled ?? 0) };
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
    async getProductPhoto(productId, color) {
      const { rows } = await pool.query(
        'SELECT mime, bytes FROM shop_product_photos WHERE product_id = $1 AND color = $2',
        [productId, color ?? '']);
      return rows[0] ? { mime: rows[0].mime, bytes: rows[0].bytes } : null;
    },
    async listProductPhotos() {
      // Deliberately without `bytes`: the panel draws a thumbnail per row and
      // the storefront asks which products have a photo. Selecting the blobs to
      // answer either would move megabytes to render a list.
      const { rows } = await pool.query(
        'SELECT product_id, color, uploaded_at FROM shop_product_photos ORDER BY product_id, color');
      return rows.map((r) => ({
        productId: r.product_id, color: r.color,
        uploadedAt: new Date(r.uploaded_at).toISOString(),
      }));
    },
    async putProductPhoto(p) {
      await pool.query(
        `INSERT INTO shop_product_photos (product_id, color, mime, bytes, uploaded_by, uploaded_at)
         VALUES ($1, $2, $3, $4, $5, now())
         ON CONFLICT (product_id, color)
         DO UPDATE SET mime = EXCLUDED.mime, bytes = EXCLUDED.bytes,
                       uploaded_by = EXCLUDED.uploaded_by, uploaded_at = now()`,
        [p.productId, p.color ?? '', p.mime, p.bytes, p.staffId ?? null]);
    },
    async deleteProductPhoto(productId, color) {
      await pool.query('DELETE FROM shop_product_photos WHERE product_id = $1 AND color = $2',
        [productId, color ?? '']);
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
