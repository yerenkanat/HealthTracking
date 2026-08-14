/**
 * The cry detector's confidence threshold, as it is actually served.
 *
 * Frame 17c. Below this the app must NOT name a reason: the screen says «не
 * уверены», keeps the probability bars, and asks for another recording. Naming
 * «голод» at 31 % reads to a mother exactly like naming it at 91 %, and this
 * screen is one she opens at 3am while deciding whether to feed a baby who is
 * actually in pain.
 *
 * Same shape as the pregnancy calendar and the vaccination schedule next door:
 * a SHIPPED DEFAULT that is compiled in, with a single optional override row on
 * top. Delete the row and the product is back to 0.45. The app carries the same
 * default as a Dart constant, so a phone with no signal still applies a
 * threshold rather than none.
 *
 * The failure policy is the point. If the database is unreachable this returns
 * the default — not an error, not zero. Zero would silently turn the rule off
 * and let a 12 %-confidence guess be announced as the reason.
 */

/** The shipped threshold. Mirrored in the app as `kCryMinConfidenceDefault`. */
export const CRY_MIN_CONFIDENCE_DEFAULT = 0.45;

/**
 * How high the back office may set it.
 *
 * Not 1: a threshold no answer ever reaches turns the screen into a permanent
 * «не уверены», and one mistyped digit should not be able to do that. Not
 * below 0 for the obvious reason — and 0 itself IS allowed, because «назвать
 * причину всегда» is a decision somebody may legitimately take once there are
 * enough verdicts to justify it.
 */
export const CRY_MIN_CONFIDENCE_MAX = 0.95;
export const CRY_MIN_CONFIDENCE_MIN = 0;

export interface CryThresholdRow {
  minConfidence: number;
  updatedAt: string;
  updatedBy: string | null;
}

/** What `GET /protocols/cry` answers with. */
export interface ServedCryThreshold {
  /** The threshold in force, 0..0.95. */
  minConfidence: number;
  /** The compiled-in value, so a reader can see what was changed FROM. */
  defaultMinConfidence: number;
  /** 'default' until somebody has actually chosen a number. */
  source: 'default' | 'override';
  updatedAt: string | null;
  /**
   * What the app must do below the threshold, in the response rather than only
   * in a Dart file — so the rule and the number cannot drift apart.
   */
  belowThreshold: 'name_no_reason';
}

/** Only the piece of the repository this needs, so tests can pass a stub. */
export interface CryThresholdSource {
  getCryThreshold(): Promise<CryThresholdRow | null>;
}

export async function servedCryThreshold(
  repo: CryThresholdSource | undefined,
): Promise<ServedCryThreshold> {
  let row: CryThresholdRow | null = null;
  try {
    // Optional-called rather than assumed: several route tests build the server
    // with a bare `{} as Repository`, and answering 500 because nobody stubbed
    // a settings table would be a worse answer than the shipped default.
    row = (await repo?.getCryThreshold?.()) ?? null;
  } catch {
    row = null;
  }
  const min = row && Number.isFinite(row.minConfidence) ? clampThreshold(row.minConfidence) : null;
  return {
    minConfidence: min ?? CRY_MIN_CONFIDENCE_DEFAULT,
    defaultMinConfidence: CRY_MIN_CONFIDENCE_DEFAULT,
    source: min == null ? 'default' : 'override',
    updatedAt: min == null ? null : row!.updatedAt,
    belowThreshold: 'name_no_reason',
  };
}

/** Keep a stored value inside the range the panel is allowed to set. */
export function clampThreshold(v: number): number {
  return Math.min(CRY_MIN_CONFIDENCE_MAX, Math.max(CRY_MIN_CONFIDENCE_MIN, v));
}
