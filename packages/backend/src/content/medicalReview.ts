/**
 * Medical guidance is checked by a clinician before anybody reads it.
 *
 * docs/CLAUDE-admin-design.md §"Публикация контента": «Медицинский текст —
 * только после проверки врачом.»
 *
 * The catalogue this back office edits tells a pregnant woman what her
 * twenty-third week means, when to worry about a movement count, and which
 * vaccinations are due. It was editable by anybody with the CMS open and went
 * live the moment it was saved, so the difference between reviewed guidance and
 * a half-remembered paragraph was invisible to the person reading it.
 *
 * Two rules, and the second is the one that actually holds:
 *
 *   1. an item marked `medical` cannot be published without a review;
 *   2. EDITING reviewed text takes the review away. Approve-then-rewrite is the
 *      obvious way around rule 1, and it is the failure that would happen by
 *      accident: somebody fixes a typo in an approved card and neither of them
 *      thinks of it as republishing medical advice.
 *
 * Who may approve is enforced elsewhere, by the capability model: reviewing
 * needs `health`, authoring needs `content`, and no role has both except an
 * owner. That is what makes this two people rather than a checkbox.
 *
 * PURE: items in, verdict out. No repository, no clock.
 */

export interface Review {
  /** The staff id who signed it off. */
  by: string;
  /** When, ISO. */
  at: string;
  /** What was signed off — see [textFingerprint]. */
  fingerprint: string;
}

export interface ReviewableItem {
  id: string;
  medical?: boolean;
  /** Not published: a draft is work in progress and reaches no reader. */
  draft?: boolean;
  title?: Record<string, string>;
  summary?: Record<string, string>;
  url?: string;
  video?: { provider: string; url: string; posterUrl?: string };
  review?: Review;
}

/**
 * A stable summary of everything a clinician actually read.
 *
 * The title, the summary in every language, and where the material itself
 * lives — swapping the video on an approved card publishes an unreviewed
 * twenty minutes of advice under a reviewed headline.
 *
 * Not a hash: this is compared, never stored as a secret, and a readable
 * fingerprint means a mismatch can be diagnosed by looking at it. Sorted keys,
 * so re-saving the same card with its languages in a different order does not
 * read as an edit and revoke a real review.
 */
export function textFingerprint(item: ReviewableItem): string {
  const dict = (d: Record<string, string> | undefined) =>
    Object.keys(d ?? {}).sort().map((k) => `${k}=${(d ?? {})[k]}`).join('');
  return [
    dict(item.title),
    dict(item.summary),
    item.url ?? '',
    item.video ? `${item.video.provider}:${item.video.url}` : '',
  ].join('');
}

/** Does this review still describe what the item says now? */
export function reviewIsCurrent(item: ReviewableItem): boolean {
  return item.review != null && item.review.fingerprint === textFingerprint(item);
}

/**
 * Carry a review forward across a save.
 *
 * Returns the item as it should be STORED. A medical card whose text is
 * unchanged keeps the signature it already had; one whose text moved loses it
 * and has to be looked at again. A card that is not medical carries no review
 * at all — an unmarked card cannot bank an approval to spend later if somebody
 * marks it medical afterwards.
 */
export function carryReview<T extends ReviewableItem>(incoming: T, previous?: ReviewableItem): T {
  if (!incoming.medical) {
    const { review: _dropped, ...rest } = incoming;
    return rest as T;
  }
  // The client never supplies its own review — that would be self-approval by
  // POST. Only what is already stored can be carried, and only if it still
  // describes the text being saved.
  const prior = previous?.review;
  if (!prior) {
    const { review: _ignored, ...rest } = incoming;
    return rest as T;
  }
  const stillTrue = prior.fingerprint === textFingerprint(incoming);
  if (!stillTrue) {
    const { review: _stale, ...rest } = incoming;
    return rest as T;
  }
  return { ...incoming, review: prior };
}

export interface ReviewProblem {
  id: string;
  /** 'never' — no clinician has ever signed this off.
   *  'stale' — one did, and the text has changed since. */
  reason: 'never' | 'stale';
}

/**
 * Which items may not go live yet.
 *
 * Drafts are exempt: a draft is how an unfinished medical card gets written at
 * all, and refusing to save one would push the work into a document nobody can
 * review.
 */
export function unreviewed(items: ReviewableItem[], previousById: Map<string, ReviewableItem>): ReviewProblem[] {
  const out: ReviewProblem[] = [];
  for (const item of items) {
    if (!item.medical || item.draft) continue;
    const prior = previousById.get(item.id)?.review;
    if (!prior) { out.push({ id: item.id, reason: 'never' }); continue; }
    if (prior.fingerprint !== textFingerprint(item)) out.push({ id: item.id, reason: 'stale' });
  }
  return out;
}

export function reviewMessage(problems: ReviewProblem[]): string {
  return problems
    .map((p) => p.reason === 'never'
      ? `«${p.id}»: медицинский текст без проверки врачом`
      : `«${p.id}»: текст изменён после проверки — нужна новая`)
    .join('; ');
}
