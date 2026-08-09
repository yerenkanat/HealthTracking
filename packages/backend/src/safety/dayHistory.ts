/**
 * Frames 47/48 — «История дня» and «Событие из истории дня».
 *
 * docs/CLAUDE-app-design.md: «карта маршрута с точками + плашка «3,2 км ·
 * 4 точки» → таймлайн событий (вышла, пришла в школу, SOS, дома) → плашка
 * «маршруты хранятся 90 дней».»
 *
 * The trail has been written on every fix since the first one and pruned at
 * ninety days, and between the two there was no way to look at it. This turns
 * the raw fixes into the two things the screen shows: a line worth drawing, and
 * a list of what happened.
 *
 * ON SIMPLIFYING. A tracker reporting every thirty seconds makes 2 880 points a
 * day. Drawn whole that is a smear, and sent whole it is half a megabyte over a
 * phone connection. The trail is thinned by distance rather than by taking
 * every Nth point: dropping every other fix loses the corner where she turned,
 * which is the part of a route anybody actually reads.
 *
 * ON DISTANCE. Summed over the THINNED points, so the figure on the screen is
 * the length of the line the screen draws. Summing the raw fixes gives a larger
 * number — GPS jitter while sitting still adds up to hundreds of metres an hour
 * — and «3,2 км» beside a line that is plainly one kilometre reads as a bug in
 * whichever number the reader trusts less.
 *
 * PURE: fixes and events in, a day's story out.
 */

export interface Fix {
  observedAt: string;
  coords: { lat: number; lng: number; accuracyM?: number };
}

/** A geofence crossing, as the events table records it. */
export interface Crossing {
  at: string;
  transition: 'enter' | 'exit';
  /** The zone's name, for «пришла в школу». Null if the zone is gone. */
  zoneName: string | null;
}

/** An SOS press. */
export interface SosPress {
  at: string;
  lat?: number;
  lng?: number;
  /** What the parent marked it as afterwards; null while still open. */
  outcome?: SosOutcome | null;
}

export type DayEventKind = 'enter' | 'exit' | 'sos';

export interface DayEvent {
  at: string;
  kind: DayEventKind;
  /** Zone name for a crossing; null for an SOS, which happens anywhere. */
  zoneName: string | null;
  lat?: number;
  lng?: number;
  /**
   * SOS only, and only once closed. The detail screen preselects the chip from
   * this, so reopening an alarm shows the verdict already recorded rather than
   * asking again — and asking again is how a second answer overwrites a first.
   */
  outcome?: SosOutcome | null;
}

export interface DayHistory {
  /** The line to draw, oldest first. */
  points: Fix[];
  /** Metres along the drawn line. */
  distanceM: number;
  /** How many points are drawn — the «4 точки» in the badge. */
  pointCount: number;
  /** What happened, oldest first. */
  events: DayEvent[];
  /** Fixes before thinning, so the screen can be honest about simplifying. */
  rawCount: number;
}

const EARTH_R = 6_371_000;

/** Metres between two coordinates. Haversine — good to a metre at city scale. */
export function metresBetween(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const la1 = toRad(a.lat);
  const la2 = toRad(b.lat);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(la1) * Math.cos(la2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Default thinning distance. Below this a phone is standing still as far as a
 * city map is concerned, and the fixes are jitter.
 */
export const MIN_STEP_M = 40;

/**
 * Keep the first fix, the last, and every one at least [minStepM] from the last
 * one kept.
 *
 * Distance-based rather than every-Nth on purpose: taking every tenth point
 * drops the corner where she turned and keeps ten identical points from the
 * half hour she sat in class. The LAST point is always kept — it is where she
 * is now, and it is the one thing on this screen somebody is looking for.
 */
export function thinTrail(fixes: Fix[], minStepM = MIN_STEP_M): Fix[] {
  if (fixes.length <= 2) return [...fixes];
  const out: Fix[] = [fixes[0]];
  for (let i = 1; i < fixes.length - 1; i++) {
    if (metresBetween(out[out.length - 1].coords, fixes[i].coords) >= minStepM) {
      out.push(fixes[i]);
    }
  }
  out.push(fixes[fixes.length - 1]);
  return out;
}

export function buildDayHistory(input: {
  fixes: Fix[];
  crossings: Crossing[];
  sos: SosPress[];
  minStepM?: number;
}): DayHistory {
  // Sorted here rather than trusted: fixes arrive out of order whenever an
  // offline tracker flushes its buffer, and a trail drawn in arrival order is
  // a line that doubles back on itself.
  const fixes = [...input.fixes].sort((a, b) => a.observedAt.localeCompare(b.observedAt));
  const points = thinTrail(fixes, input.minStepM ?? MIN_STEP_M);

  let distanceM = 0;
  for (let i = 1; i < points.length; i++) {
    distanceM += metresBetween(points[i - 1].coords, points[i].coords);
  }

  const events: DayEvent[] = [
    ...input.crossings.map((c) => ({
      at: c.at,
      kind: c.transition as DayEventKind,
      zoneName: c.zoneName,
    })),
    ...input.sos.map((s) => ({
      at: s.at,
      kind: 'sos' as const,
      zoneName: null,
      lat: s.lat,
      lng: s.lng,
      outcome: s.outcome ?? null,
    })),
  ].sort((a, b) => a.at.localeCompare(b.at));

  return {
    points,
    distanceM: Math.round(distanceM),
    pointCount: points.length,
    events,
    rawCount: fixes.length,
  };
}

/**
 * Frame 48 — «Чем закончилось». What a parent can mark an SOS as, afterwards.
 *
 * Four, and no free-text box. A parent closing an alarm at midnight will not
 * write a paragraph, and an outcome field that is usually empty tells nobody
 * anything. These four are the ones that change what we would do next time.
 */
export const SOS_OUTCOMES = [
  { key: 'false_press', ru: 'Случайное нажатие', kk: 'Кездейсоқ басу' },
  { key: 'scared', ru: 'Испугалась, всё хорошо', kk: 'Қорықты, бәрі жақсы' },
  { key: 'needed_help', ru: 'Нужна была помощь', kk: 'Көмек қажет болды' },
  { key: 'unknown', ru: 'Не удалось выяснить', kk: 'Анықтай алмадық' },
] as const;

export type SosOutcome = (typeof SOS_OUTCOMES)[number]['key'];

export function isSosOutcome(v: unknown): v is SosOutcome {
  return typeof v === 'string' && SOS_OUTCOMES.some((o) => o.key === v);
}
