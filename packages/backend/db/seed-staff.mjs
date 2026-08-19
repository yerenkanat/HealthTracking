#!/usr/bin/env node
/**
 * Create or update a staff account for the back office.
 *
 *   STAFF_PHONE=7073452244 STAFF_PASSWORD='…' node db/seed-staff.mjs
 *   STAFF_PHONE=7071112233 STAFF_ROLE=support STAFF_NAME='Айгерім' node db/seed-staff.mjs
 *   STAFF_PHONE=7071112244 STAFF_ROLE=warehouse STAFF_NAME='…' node db/seed-staff.mjs
 *
 * STAFF_ROLE accepts every role in src/auth/capabilities.ts — owner, operator,
 * seller, warehouse, content, admin, clinician, support — and defaults to
 * `admin` because the documented use of this script is recovering a lockout
 * (src/routes/staffAdmin.ts names it for exactly that). Pass a narrower role
 * whenever the job is narrower: `admin` carries health and finance, i.e. a
 * mother's medical record and a child's location.
 *
 * The password is read from the environment and never written anywhere but the
 * scrypt hash — not to a file, not to the log, not to the shell history if you
 * use a leading space or a here-doc.
 *
 * Idempotent: running it again with a new password is how a password is
 * changed.
 */
import { Pool } from 'pg';
import { randomBytes, scrypt } from 'node:crypto';
import { promisify } from 'node:util';

/**
 * The roles come from the ONE place the capability matrix lives, not from a
 * copy.
 *
 * This script used to validate against a literal ['admin','clinician','support']
 * while src/routes/staffAdmin.ts had already moved to the full STAFF_ROLES —
 * and staffAdmin.ts names THIS script as the recovery route out of a lockout.
 * So after a lockout the owner would SSH in, run `STAFF_ROLE=warehouse …`, get
 * exit 2, and the only role the script still accepted was `admin` = every
 * capability there is. A warehouse hand seeded from the shell came out holding
 * `health` and `finance`: a mother's medical record and a child's location.
 * Reading the shared list is what stops that drifting apart a second time.
 *
 * Imported from a .ts source deliberately: the backend runs its TypeScript
 * directly under Node's type stripping (Node >= 22.18; the deploy image is
 * node:24-alpine, see deploy/landing-stack.sh). If that ever fails, say so in
 * words the person recovering a lockout can act on rather than dying with
 * "Unknown file extension .ts".
 */
let STAFF_ROLES;
try {
  ({ STAFF_ROLES } = await import('../src/auth/capabilities.ts'));
} catch (err) {
  console.error('Could not read the role list from src/auth/capabilities.ts:');
  console.error(`  ${err?.message ?? err}`);
  console.error('This needs Node >= 22.18 for TypeScript type stripping. Run it in the');
  console.error('deploy image instead, from the repo root on the box:');
  console.error('  docker run --rm --network supabase_default -v /opt/umay:/app \\');
  console.error('    -w /app/packages/backend --env-file /etc/umay/backend.env \\');
  console.error('    -e STAFF_PHONE -e STAFF_PASSWORD -e STAFF_ROLE -e STAFF_NAME \\');
  console.error('    node:24-alpine node db/seed-staff.mjs');
  process.exit(2);
}

const scryptAsync = promisify(scrypt);

/** Must match http/staffAuth.ts — same scheme, same length. */
async function hashPassword(password) {
  const salt = randomBytes(16);
  const hash = await scryptAsync(password, salt, 64);
  return `scrypt$${salt.toString('hex')}$${hash.toString('hex')}`;
}

/** Same normalisation the login uses, or the account cannot be signed into. */
function normalizePhone(input) {
  const digits = String(input ?? '').replace(/\D/g, '');
  if (digits.length === 11 && digits.startsWith('8')) return `7${digits.slice(1)}`;
  if (digits.length === 10) return `7${digits}`;
  return digits;
}

const phone = normalizePhone(process.env.STAFF_PHONE ?? '');
const password = process.env.STAFF_PASSWORD ?? '';
const role = process.env.STAFF_ROLE ?? 'admin';
const name = process.env.STAFF_NAME ?? '';

if (!phone || phone.length < 10) {
  console.error('STAFF_PHONE is required (a real phone number)');
  process.exit(2);
}
if (password.length < 8) {
  console.error('STAFF_PASSWORD is required and must be at least 8 characters');
  process.exit(2);
}
if (!STAFF_ROLES.includes(role)) {
  console.error(`STAFF_ROLE must be one of: ${STAFF_ROLES.join(', ')} (got ${role})`);
  console.error('Grant the narrowest role that does the job. `admin` is EVERY');
  console.error('capability, including health and finance.');
  process.exit(2);
}

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
try {
  await pool.query(
    `INSERT INTO staff_accounts (phone, password_hash, role, display_name)
     VALUES ($1,$2,$3,$4)
     ON CONFLICT (phone) DO UPDATE
       SET password_hash = EXCLUDED.password_hash,
           role          = EXCLUDED.role,
           display_name  = EXCLUDED.display_name`,
    [phone, await hashPassword(password), role, name],
  );
  // Any existing session for this account is now stale — changing a password
  // has to sign the old sessions out, or it does not achieve what it is for.
  const { rowCount } = await pool.query(
    `DELETE FROM staff_sessions WHERE staff_id IN
       (SELECT id FROM staff_accounts WHERE phone = $1)`,
    [phone],
  );
  console.log(`staff account ready: ${phone} (${role})`);
  if (rowCount > 0) console.log(`  signed out ${rowCount} existing session(s)`);
} finally {
  await pool.end();
}
