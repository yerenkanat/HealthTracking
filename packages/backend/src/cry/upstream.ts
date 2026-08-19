/**
 * How a call to the cry-classifier ENDED, kept instead of thrown away.
 *
 * `/cry/analyze` used to answer a flat 502 for every way the upstream call
 * could fail, so three completely different situations reached the phone as one
 * string:
 *
 *  - the classifier answered **503**: it is running and it CANNOT analyse —
 *    today because there is no trained `model.pkl` at all
 *    (`packages/cry-classifier/app/main.py` `_load_model` returns early and
 *    `predict_cry` raises 503). Recording again is guaranteed to fail;
 *  - the classifier answered **400/413/415/422**: it read the request and could
 *    not make audio out of it. That is about the clip, not about the service,
 *    and another recording genuinely may work;
 *  - nothing answered at all — connection refused, DNS, a timeout, a 5xx. We do
 *    not know anything about the service; the clip simply never got analysed.
 *
 * These are pure functions over the failure so the mapping can be tested
 * without a socket, and so the route stays a two-liner.
 */

/** The classifier answered, with a status we did not want. */
export class CryUpstreamError extends Error {
  constructor(readonly status: number) {
    super(`cry-classifier ${status}`);
    this.name = 'CryUpstreamError';
  }
}

/** What the app is told, and what it may conclude from it. */
export type CryFailure =
  /** The analyser says it cannot analyse. Retrying is pointless. */
  | 'unavailable'
  /** The analyser could not read this clip. Another recording may work. */
  | 'unreadable'
  /** No answer reached us. We know nothing about the analyser. */
  | 'unreachable';

/**
 * Statuses that mean "your upload was the problem".
 *
 * 429 and 408 are deliberately NOT here: a rate limit or a timeout is us, and
 * telling her the recording was unreadable would send her to re-record for a
 * reason that has nothing to do with her audio.
 */
const AUDIO_FAULT = new Set([400, 413, 415, 422]);

/** Classify whatever `cryAnalyze` threw. */
export function cryFailureFor(err: unknown): CryFailure {
  const status = err instanceof CryUpstreamError ? err.status : null;
  if (status === 503) return 'unavailable';
  if (status !== null && AUDIO_FAULT.has(status)) return 'unreadable';
  return 'unreachable';
}

/** The HTTP status and body this proxy answers for a given failure. */
export function cryFailureReply(failure: CryFailure): { status: number; body: { error: string; reason?: string } } {
  switch (failure) {
    case 'unavailable':
      // 503 all the way down: the app must be able to tell "cannot answer" from
      // "did not answer", and re-using the upstream's own status is the least
      // surprising way to say it.
      return { status: 503, body: { error: 'cry_service_unavailable', reason: 'model_unavailable' } };
    case 'unreadable':
      return { status: 400, body: { error: 'cry_audio_unreadable' } };
    case 'unreachable':
      return { status: 502, body: { error: 'cry_upstream_unavailable' } };
  }
}
