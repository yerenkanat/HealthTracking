/**
 * App version policy — the minimum build the API will support and the latest
 * build available, served at GET /app/version (public, no auth). The app checks
 * this on launch: below minBuild it blocks behind a force-update screen; below
 * latestBuild it shows a soft "update available" nudge.
 *
 * The floor exists so a client too old to speak the current API — or missing a
 * safety fix in the triage/emergency path — can be turned away cleanly instead
 * of failing in obscure ways. Values come from the environment so ops can raise
 * the floor at release time without a code change; the defaults keep the gate
 * inert (minBuild 0 blocks nobody) until a floor is deliberately set.
 */

export interface AppVersionInfo {
  /** Builds below this are blocked. 0 = no floor (blocks nobody). */
  minBuild: number;
  /** The newest build available, for the soft "update available" nudge. */
  latestBuild: number;
  /** Optional message shown on the update screen, per locale. */
  message: { ru: string; kk: string; en: string } | null;
}

function intFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined) return fallback;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

export function appVersionInfo(): AppVersionInfo {
  return {
    minBuild: intFromEnv('APP_MIN_BUILD', 0),
    latestBuild: intFromEnv('APP_LATEST_BUILD', 1),
    message: null,
  };
}
