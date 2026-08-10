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

/**
 * The SMS code gate — whether `REQUIRE_PHONE_CODE=1` can actually do anything.
 *
 * It cannot, today, anywhere it matters. `smsSender()` in index.ts returns a
 * sender ONLY under the dev shortcuts (no DATABASE_URL / USE_MEMORY_DB), so on
 * every real deployment it returns undefined and
 * `REQUIRE_PHONE_CODE === '1' && !!smsSender()` is false however the variable is
 * set. Setting it on the server changes nothing: sign-in still accepts any
 * number with no verification.
 *
 * That is a documentation problem as much as a code one — docs/RELEASE.md
 * listed the variable as the mitigation — so the impossibility is made
 * VISIBLE rather than quietly corrected: a loud line at boot, and the SMS row
 * on «Интеграции» saying the flag is being ignored. No gateway is invented
 * here; there still isn't one.
 */
export interface PhoneCodePosture {
  /** REQUIRE_PHONE_CODE=1 — what the operator asked for. */
  requested: boolean;
  /** A sender was actually injected. Without one no code can leave the server. */
  senderWired: boolean;
  /** What buildServer is given: the gate engages only when BOTH are true. */
  effective: boolean;
  /** Asked for and impossible — the state the warning exists for. */
  ignored: boolean;
  /** The boot line, or null when there is nothing to say. */
  warning: string | null;
}

/**
 * The warning text, in one place, because two callers say it: the composition
 * root (at boot) and buildServer (which is what the tests can reach).
 */
export function phoneCodeWarning(requested: boolean, senderWired: boolean): string | null {
  if (!requested || senderWired) return null;
  return (
    'REQUIRE_PHONE_CODE=1 is set but NO SMS sender is wired, so the code gate is ' +
    'OFF and this variable is doing nothing. Phone sign-in still accepts any ' +
    'number with no verification — anyone who knows a customer\'s number can ' +
    'open her account, her children and their live locations. Setting the ' +
    'variable is not enough: smsSender() in src/index.ts returns a sender only ' +
    'without a DATABASE_URL, so a real gateway has to be returned there. See ' +
    'docs/RELEASE.md and «Интеграции» in the admin panel.'
  );
}

export function phoneCodePosture(
  env: NodeJS.ProcessEnv, senderWired: boolean,
): PhoneCodePosture {
  const requested = env.REQUIRE_PHONE_CODE === '1';
  return {
    requested,
    senderWired,
    effective: requested && senderWired,
    ignored: requested && !senderWired,
    warning: phoneCodeWarning(requested, senderWired),
  };
}
