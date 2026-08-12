/**
 * Frame 06 «Маркетинг» — the рассылка half.
 *
 * One message, written once, to a named group of mothers. Everything here is
 * PURE: which fields a segment may name, who a segment matches, and how often
 * a person may be written to. No Fastify, no repository — so the memory
 * repository and the Postgres one can be held to the same answers, and so the
 * two rules that make this survivable are testable as data.
 *
 * THE TWO RULES.
 *
 *  1. «Не чаще раза в неделю». A woman is written to at most once every
 *     [BROADCAST_MIN_GAP_DAYS] days, ACROSS broadcasts — not once per
 *     broadcast. Two campaigns published on the same afternoon are exactly the
 *     case the rule exists for, and a per-broadcast cap would let both through.
 *     Enforced when a broadcast is published, against a delivery ledger, so it
 *     survives a restart and cannot be argued with by a second panel tab.
 *
 *  2. A segment names only what the schema honestly knows about a person:
 *     her language, whether she is pregnant, and how old her children are.
 *     `users.locale`, `users.due_date`, `children.date_of_birth`. Nothing else
 *     — see [validateSegment] for why a blood-pressure segment is refused
 *     rather than ignored.
 */

/** Days between two messages to the same woman. The panel's footer prints it. */
export const BROADCAST_MIN_GAP_DAYS = 7;

/** «Мамы малышей» means a child younger than this. */
export const INFANT_MAX_MONTHS = 12;

/**
 * Who a broadcast goes to.
 *
 * A closed list rather than a query language. Every option is answerable from
 * one column that the product already fills in for its own reasons, and an
 * option nobody can compute is worse than an option nobody has.
 */
export const BROADCAST_AUDIENCES = ['all', 'pregnant', 'mothers', 'infants'] as const;
export type BroadcastAudience = (typeof BROADCAST_AUDIENCES)[number];

export const BROADCAST_LOCALES = ['ru', 'kk'] as const;
export type BroadcastLocale = (typeof BROADCAST_LOCALES)[number];

export interface BroadcastSegment {
  /** Absent means everybody. */
  audience?: BroadcastAudience;
  /** Absent means both languages. */
  locale?: BroadcastLocale;
}

/** The only keys a stored segment may carry. Everything else is refused. */
export const SEGMENT_FIELDS = ['audience', 'locale'] as const;

/**
 * Fields somebody will reach for, and the reason each is not here.
 *
 * Named explicitly so the refusal is a sentence rather than «validation
 * failed». A marketer who asks for «женщины с высоким давлением» is asking a
 * reasonable-sounding question with an unacceptable answer, and the screen has
 * to say which.
 */
const HEALTH_WORDS =
  /(bp|pressure|systolic|diastolic|glucose|sugar|hr|heart|pulse|spo2|temp|weight|cycle|period|triage|severity|emergency|sos|alert|diagnos|давлен|глюкоз|пульс|вес|цикл)/i;

export interface SegmentProblem {
  field: string;
  /** True when the field is health data, which is refused rather than unsupported. */
  health: boolean;
  message: string;
}

/**
 * Is this a segment we will store?
 *
 * Returns the problems, empty when it is fine. UNKNOWN FIELDS ARE REFUSED, not
 * dropped: a segment saved as `{}` after somebody typed a blood-pressure rule
 * would send the message to every woman in the country while the panel showed
 * the rule they wrote. Refusing is the only outcome that cannot mislead.
 *
 * Health data is called out by name. «Показатели здоровья» are special-category
 * (GDPR Art.9) and this product collects them to warn a woman about her own
 * pregnancy — using them to choose who gets an advertisement is a different
 * purpose entirely, and it is not one anybody consented to.
 */
export function validateSegment(raw: unknown): SegmentProblem[] {
  const problems: SegmentProblem[] = [];
  if (raw == null) return problems;
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return [{
      field: '(сегмент)', health: false,
      message: 'Сегмент должен быть объектом вида {"audience":"pregnant","locale":"kk"}.',
    }];
  }
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (value === undefined || value === null) continue;
    if (!(SEGMENT_FIELDS as readonly string[]).includes(key)) {
      const health = HEALTH_WORDS.test(key);
      problems.push({
        field: key,
        health,
        message: health
          ? `Нельзя выбирать получателей по полю «${key}»: показатели здоровья собраны, чтобы предупредить женщину о её беременности, ` +
            'и не могут решать, кому уходит рассылка. Доступные признаки: язык, срок беременности, возраст ребёнка.'
          : `Признак «${key}» недоступен: сегмент строится только по языку (locale) и аудитории (audience) — ` +
            'это единственное, что база знает о человеке честно.',
      });
      continue;
    }
    if (key === 'audience' && !(BROADCAST_AUDIENCES as readonly unknown[]).includes(value)) {
      problems.push({
        field: key, health: false,
        message: `Аудитория «${String(value)}» не существует. Доступно: ${BROADCAST_AUDIENCES.join(', ')}.`,
      });
    }
    if (key === 'locale' && !(BROADCAST_LOCALES as readonly unknown[]).includes(value)) {
      problems.push({
        field: key, health: false,
        message: `Язык «${String(value)}» не существует. Доступно: ${BROADCAST_LOCALES.join(', ')}.`,
      });
    }
  }
  return problems;
}

/** The problems as one sentence the panel prints verbatim. */
export function segmentMessage(problems: SegmentProblem[]): string {
  return problems.map((p) => p.message).join(' ');
}

/** Only the recognised keys, in a stable order, with absent meaning "everyone". */
export function normalizeSegment(raw: unknown): BroadcastSegment {
  const src = (raw ?? {}) as Record<string, unknown>;
  const out: BroadcastSegment = {};
  if ((BROADCAST_AUDIENCES as readonly unknown[]).includes(src.audience)) {
    out.audience = src.audience as BroadcastAudience;
  }
  if ((BROADCAST_LOCALES as readonly unknown[]).includes(src.locale)) {
    out.locale = src.locale as BroadcastLocale;
  }
  return out;
}

/**
 * What the segment needs to know about one person.
 *
 * Three facts, each from a column that exists. `childDobs` is a list because a
 * woman with a five-year-old and a newborn is a mother of an infant.
 */
export interface AudienceRow {
  userId: string;
  /** `users.locale` — 'ru-KZ', 'kk', null. */
  locale: string | null;
  /** `users.due_date`, yyyy-MM-dd. */
  dueDate: string | null;
  /**
   * How many children she has at all.
   *
   * Separate from [childDobs] on purpose: a woman who added her baby without a
   * birthday is still a mother, and «мамы» must include her. Only «мамы детей
   * до года» needs a date, and she is honestly absent from that one rather
   * than guessed into it.
   */
  childCount: number;
  /** `children.date_of_birth`, yyyy-MM-dd, nulls dropped. */
  childDobs: string[];
}

/** 'ru-KZ' → 'ru'. Anything unrecognised counts as Russian, the app's default. */
export function shortLocale(raw: string | null | undefined): BroadcastLocale {
  return (raw ?? '').toLowerCase().startsWith('kk') ? 'kk' : 'ru';
}

/** Whole days from [from] to [to], both UTC midnights. */
export function daysBetween(from: Date, to: Date): number {
  return Math.floor((to.getTime() - from.getTime()) / 86_400_000);
}

/** Midnight UTC of the day [d] falls in — dates in this schema are days. */
export function utcDay(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function ageInMonths(dob: string, today: Date): number | null {
  const d = new Date(`${dob}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return null;
  return Math.floor(daysBetween(utcDay(d), utcDay(today)) / 30.4375);
}

/**
 * Does this woman belong to the segment?
 *
 * The in-memory repository calls this directly; the Postgres one expresses the
 * same three questions in SQL. The definitions live here so the two cannot
 * drift on what «беременные» means — the failure that would show up as a test
 * suite agreeing with itself while production sent the message to the wrong
 * half of the country.
 */
export function matchesSegment(
  row: AudienceRow, segment: BroadcastSegment, today: Date,
): boolean {
  if (segment.locale && shortLocale(row.locale) !== segment.locale) return false;
  switch (segment.audience ?? 'all') {
    case 'all':
      return true;
    // Pregnant NOW: a due date that has not passed. An overdue date is not a
    // pregnancy the database can vouch for — she may have given birth three
    // weeks ago and nobody told us — and «поздравляем с беременностью» to a
    // woman holding her baby is the worst message this feature can send.
    case 'pregnant': {
      if (!row.dueDate) return false;
      const due = new Date(`${row.dueDate}T00:00:00Z`);
      if (Number.isNaN(due.getTime())) return false;
      return daysBetween(utcDay(today), utcDay(due)) >= 0;
    }
    case 'mothers':
      return row.childCount > 0;
    case 'infants':
      return row.childDobs.some((dob) => {
        const m = ageInMonths(dob, today);
        return m != null && m >= 0 && m < INFANT_MAX_MONTHS;
      });
  }
}

/** «Беременные · только қаз» — what the table row and the audit entry say. */
export function describeSegment(segment: BroadcastSegment): string {
  const audience = {
    all: 'Все',
    pregnant: 'Беременные',
    mothers: 'Мамы',
    infants: `Мамы детей до ${INFANT_MAX_MONTHS} мес.`,
  }[segment.audience ?? 'all'];
  const locale = segment.locale === 'kk' ? ' · только қаз'
    : segment.locale === 'ru' ? ' · только рус' : '';
  return `${audience}${locale}`;
}
