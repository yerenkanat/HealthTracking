#!/usr/bin/env node
/**
 * Create or update a staff account for the back office.
 *
 *   STAFF_PHONE=7073452244 STAFF_PASSWORD='…' node db/seed-staff.mjs
 *   STAFF_PHONE=7071112233 STAFF_ROLE=support STAFF_NAME='Айгерім' node db/seed-staff.mjs
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
if (!['admin', 'clinician', 'support'].includes(role)) {
  console.error(`STAFF_ROLE must be admin, clinician or support (got ${role})`);
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
