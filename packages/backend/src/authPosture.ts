/**
 * The boot guard's auth decision, kept in its own side-effect-free module so it
 * can be tested without importing index.ts (which starts the server on import).
 *
 * `authUser` becomes real with `REAL_AUTH=1` + a Firebase service account.
 *
 * `authAdmin` is real now: staff sign in with a phone number and a password and
 * carry a session cookie (migration 019, routes/staffLogin.ts). The header
 * shortcut it replaced survives for local development ONLY, where there is no
 * database to hold an account — and that is the condition this reports on.
 *
 * The two are reported separately because they fail differently: a stubbed user
 * path exposes families' data to anyone who can send a header, a stubbed admin
 * path hands over the back office. Reading either as "everything is
 * authenticated" is the mistake that would ship one of them open.
 */
export function authPosture(env: NodeJS.ProcessEnv): {
  userStub: boolean;
  adminStub: boolean;
  safeForProduction: boolean;
} {
  // The user path is a stub when the dev shortcuts are live — the `stub-token:`
  // bearer and the `x-user-id` header. Both are gated on the absence of a
  // database, the same rule as the staff shortcut.
  //
  // This used to read `REAL_AUTH !== '1'`, which was about Firebase alone. The
  // app now signs in against our own server (POST /auth/phone), so a deployment
  // with a database has real user auth whether or not Firebase is configured —
  // and, more to the point, one WITHOUT a database has forgeable auth no matter
  // what REAL_AUTH says.
  const devShortcuts = env.USE_MEMORY_DB === 'true' || !env.DATABASE_URL;
  const userStub = devShortcuts;
  // Mirrors ALLOW_HEADER_STAFF in index.ts: the x-staff-role shortcut is
  // honoured only with no database, or with USE_MEMORY_DB set explicitly.
  // Wherever Postgres is configured — which is every deployment — the only way
  // in is a real session.
  //
  // Deliberately derived from the database configuration rather than from a
  // flag of its own: a variable named something like ADMIN_AUTH_OK could be set
  // by anyone in a hurry, and would then wave a stub through in production.
  const adminStub = devShortcuts;
  return { userStub, adminStub, safeForProduction: !userStub && !adminStub };
}
