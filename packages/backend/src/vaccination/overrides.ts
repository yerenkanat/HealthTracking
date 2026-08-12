/**
 * The national immunisation calendar, as edited.
 *
 * Frames 15 «Вакцинация», 15a «Добавить прививку», 15b «История версий». The
 * schedule is sixteen entries that decide what every parent in this app is told
 * to do and when, and it shipped as a compiled-in JSON file: moving the second
 * pneumococcal dose meant a backend release and a store rollout.
 *
 * The rule, in one line: **the contract is the baseline, the database is a
 * patch.** Nothing here ever removes a shipped vaccine. Drop every row and the
 * served schedule is byte-for-byte the shipped one again.
 *
 * PURE: contract in, rows in, schedule out. No repository, no clock, no
 * Fastify — so the merge is exercised by unit tests and by the route tests
 * without a database between them.
 */

import type { VaccinationSchedule, Vaccine } from './schedule.js';
import type { ReviewableItem } from '../content/medicalReview.js';

/** What a parent reads on one row: the name, and the line under it. */
export interface VaccineText {
  name: string;
  note: string;
}

/** One edited or added injection, as the repository stores it. */
export interface VaccinationOverride {
  /** `<id>/<dose>` — see [vaccineKeyOf]. */
  key: string;
  id: string;
  atMonth: number;
  dose: number | null;
  ru: VaccineText;
  kk: VaccineText;
  /** Not in the contract: appended by the merge rather than patching. */
  added: boolean;
  /** Work in progress: stored, never served. */
  draft: boolean;
  review: { by: string; at: string; fingerprint: string } | null;
  /** Save counter; the served version is contract + Σ rev. */
  rev: number;
  updatedAt: string;
  updatedBy: string | null;
}

/** The one editable knob: how long a vaccine reads as «пора». */
export interface VaccinationSettings {
  dueWindowMonths: number;
  rev: number;
  updatedAt: string;
  updatedBy: string | null;
}

/** One vaccine as the app and the panel receive it. */
export interface ServedVaccine {
  /** The tick key — `<id>/<dose>`. Sent so an API consumer need not re-derive it. */
  key: string;
  id: string;
  atMonth: number;
  dose?: number;
  /** The Russian label. Always present: the contract carries one for every shipped entry. */
  ru: string;
  /**
   * The Kazakh label, and the two notes — present ONLY when the back office has
   * supplied them.
   *
   * Absent is not empty. The contract has no Kazakh and no notes at all: those
   * live in the app's own l10n table under `vac_<id>` / `vac_<id>_note`, which
   * is a better Kazakh label than anything this merge could invent. Sending
   * `kk: ''` would tell the app "the back office says this vaccine has no
   * Kazakh name" and blank a row that reads perfectly well today.
   */
  kk?: string;
  ruNote?: string;
  kkNote?: string;
  /** Added in the back office — the app has no l10n key to fall back on. */
  added?: boolean;
}

export interface ServedVaccinationSchedule {
  version: number;
  dueWindowMonths: number;
  vaccines: ServedVaccine[];
}

/**
 * The stable identity of one injection.
 *
 * Byte-identical to `vaccineKey()` in app/lib/domain/vaccination.dart —
 * `'${v.id}/${v.dose}'`, which for a single-dose vaccine interpolates Dart's
 * null as the four letters `null`. That looks like a bug and is not: it is the
 * string already sitting in `child_vaccines.vaccine_key` for every BCG a mother
 * has ever ticked, and "tidying" it here would silently disconnect the coverage
 * figures from the ticks they count.
 */
export function vaccineKeyOf(id: string, dose: number | null | undefined): string {
  return `${id}/${dose ?? null}`;
}

/** The contract's own entries, each carrying its key. */
export function contractKey(v: Vaccine): string {
  return vaccineKeyOf(v.id, v.dose ?? null);
}

/**
 * Contract + overrides, in the shape the app and the panel already read.
 *
 * Drafts are skipped, and skipping is the ONLY way anything ever leaves the
 * calendar. A drafted edit lets the shipped entry show through again; a drafted
 * `added` row disappears. Both are reversible, and neither destroys the words
 * somebody wrote — which is what makes the medical-review rule workable rather
 * than a wall.
 *
 * An override for a key the contract does not have and that is not `added` is
 * ignored rather than appended: it is a leftover from a vaccine the contract
 * once had, and resurrecting it as a new entry would put an injection on a
 * parent's screen that nobody currently intends.
 *
 * Ordering is by age, and within an age the contract's own order first. The app
 * groups the list by `atMonth` for its timeline and the panel prints it as a
 * table; a vaccine moved from month 4 to month 3 has to land among the month-3
 * entries or the screen silently reorders around it.
 *
 * The version moves whenever the tables move: `contract.version + Σ rev` over
 * ALL rows, drafts included, plus the settings row's own rev. Drafting changes
 * what readers see, so it has to count. `rev` only ever grows and rows are
 * never deleted, so the number is monotonic while the database is reachable —
 * a client caching by version can trust it.
 */
export function mergeSchedule(
  base: VaccinationSchedule,
  overrides: VaccinationOverride[],
  settings: VaccinationSettings | null,
): ServedVaccinationSchedule {
  const byKey = new Map(overrides.map((o) => [o.key, o]));

  const shipped: ServedVaccine[] = base.vaccines.map((v) => {
    const key = contractKey(v);
    const o = byKey.get(key);
    const out: ServedVaccine = { key, id: v.id, atMonth: v.atMonth, ru: v.ru };
    if (v.dose != null) out.dose = v.dose;
    if (!o || o.draft) return out;
    out.atMonth = o.atMonth;
    // `|| v.ru`: a stored row cannot legally hold an empty name — the route
    // refuses one — but a blank label is an unreadable row, and the contract's
    // is a better answer than nothing if one ever gets in.
    out.ru = o.ru.name.trim() || v.ru;
    if (o.kk.name.trim()) out.kk = o.kk.name;
    if (o.ru.note.trim()) out.ruNote = o.ru.note;
    if (o.kk.note.trim()) out.kkNote = o.kk.note;
    return out;
  });

  const shippedKeys = new Set(shipped.map((v) => v.key));
  const added: ServedVaccine[] = [];
  for (const o of overrides) {
    if (o.draft || !o.added || shippedKeys.has(o.key)) continue;
    const out: ServedVaccine = {
      key: o.key, id: o.id, atMonth: o.atMonth, ru: o.ru.name, added: true,
    };
    if (o.dose != null) out.dose = o.dose;
    if (o.kk.name.trim()) out.kk = o.kk.name;
    if (o.ru.note.trim()) out.ruNote = o.ru.note;
    if (o.kk.note.trim()) out.kkNote = o.kk.note;
    added.push(out);
  }
  // Deterministic among themselves, so two added vaccines at the same age come
  // out in the same order on every request rather than in row order.
  added.sort((a, b) => a.key.localeCompare(b.key));

  // Stable sort by age: shipped entries keep the contract's order within an
  // age, and anything added lands after them.
  const all = [...shipped, ...added];
  const rank = new Map(all.map((v, i) => [v, i]));
  all.sort((a, b) => a.atMonth - b.atMonth || rank.get(a)! - rank.get(b)!);

  const bump = overrides.reduce((t, o) => t + (Number.isFinite(o.rev) ? o.rev : 0), 0);
  return {
    version: base.version + bump + (settings ? settings.rev : 0),
    dueWindowMonths: settings ? settings.dueWindowMonths : base.dueWindowMonths,
    vaccines: all,
  };
}

/**
 * One vaccine, as the medical-review machinery sees it.
 *
 * content/medicalReview.ts fingerprints `title`, `summary`, `url` and `video` —
 * the shape a timeline card has. A calendar row is not a card, so rather than a
 * second fingerprint function that could drift from the first, the row is
 * projected onto that shape ONCE, here, and every rule (`unreviewed`,
 * `carryReview`, `textFingerprint`) then applies unchanged.
 *
 * What matters is that everything a clinician read is inside the projection.
 * The names and notes obviously are. So is **`atMonth`**, carried in `url`, and
 * it is the one that would be easiest to leave out and worst to: the age is the
 * whole clinical claim. «Пневмококковая, доза 2» approved at four months and
 * then quietly moved to nine months is unreviewed medical advice under a
 * reviewed headline, and it is the exact edit this frame exists to enable.
 *
 * `medical: true` unconditionally. Every row of this calendar tells a parent to
 * take a child for an injection on a date — there is no non-medical half of it.
 *
 * `base` is the contract's entry. It is passed for the same reason the
 * pregnancy editor passes one: the panel reads the MERGED row out of
 * `GET /admin/vaccination/schedule` and posts it straight back, so the
 * signature has to be taken over what a reader sees rather than over whatever a
 * particular row happens to hold. For a vaccine whose note has never been
 * edited, the panel's box is empty and the contract has no note either — both
 * sides therefore fingerprint the empty string, and the two agree.
 */
export function vaccineAsReviewable(
  key: string,
  v: {
    atMonth: number;
    dose: number | null;
    ru: VaccineText;
    kk: VaccineText;
    draft: boolean;
  },
  base?: Vaccine | null,
): ReviewableItem {
  return {
    id: `vaccine-${key}`,
    medical: true,
    draft: v.draft,
    title: { ru: v.ru.name.trim() || base?.ru || '', kk: v.kk.name.trim() },
    summary: { ru: v.ru.note.trim(), kk: v.kk.note.trim() },
    // The age is the advice. Dose too, though it cannot legally move.
    url: `atMonth=${v.atMonth};dose=${v.dose ?? ''}`,
  };
}

/**
 * A human label for an age in months, in the words the panel and the app use.
 *
 * Here rather than only in the browser because the impact and coverage routes
 * put ages into sentences a person reads, and «затронет 6 104 детей на 4 мес.»
 * assembled in two places drifts.
 */
export function ageLabelRu(months: number): string {
  if (months === 0) return 'при рождении';
  if (months < 12) return `${months} мес.`;
  const years = Math.floor(months / 12);
  const rest = months % 12;
  const y = years === 1 ? 'год' : years < 5 ? 'года' : 'лет';
  return rest === 0 ? `${years} ${y}` : `${years} г ${rest} мес.`;
}
