/**
 * Child demographics — pure aggregation shared by the memory and pg repositories
 * (and the tests) so the gender split and age buckets are computed one way.
 */
import type { ChildrenStats } from '../db/repository';

export interface ChildRow {
  gender?: string | null; // 'boy' | 'girl' | null
  dateOfBirth?: string | null; // ISO date or null
}

/** Age buckets, in order. Upper bound is exclusive, in months. */
export const AGE_BUCKETS: Array<{ bucket: string; maxMonths: number }> = [
  { bucket: '0–1', maxMonths: 12 },
  { bucket: '1–3', maxMonths: 36 },
  { bucket: '3–7', maxMonths: 84 },
  { bucket: '7+', maxMonths: Infinity },
];

/** Whole months between two ISO dates (dob → asOf), floored, never negative. */
export function ageInMonths(dobIso: string, asOfIso: string): number {
  const dob = new Date(dobIso);
  const asOf = new Date(asOfIso);
  if (isNaN(dob.getTime()) || isNaN(asOf.getTime())) return 0;
  let months = (asOf.getFullYear() - dob.getFullYear()) * 12 + (asOf.getMonth() - dob.getMonth());
  if (asOf.getDate() < dob.getDate()) months -= 1; // not a full month yet
  return Math.max(0, months);
}

export function bucketForMonths(months: number): string {
  return (AGE_BUCKETS.find((b) => months < b.maxMonths) ?? AGE_BUCKETS[AGE_BUCKETS.length - 1]).bucket;
}

export function computeChildrenStats(children: ChildRow[], asOfIso: string): ChildrenStats {
  let boys = 0, girls = 0, unknown = 0, withDob = 0;
  const counts = new Map<string, number>(AGE_BUCKETS.map((b) => [b.bucket, 0]));
  for (const c of children) {
    if (c.gender === 'boy') boys++;
    else if (c.gender === 'girl') girls++;
    else unknown++;
    if (c.dateOfBirth) {
      withDob++;
      const b = bucketForMonths(ageInMonths(c.dateOfBirth, asOfIso));
      counts.set(b, (counts.get(b) ?? 0) + 1);
    }
  }
  return {
    total: children.length,
    boys,
    girls,
    unknown,
    withDob,
    byAge: AGE_BUCKETS.map((b) => ({ bucket: b.bucket, count: counts.get(b.bucket) ?? 0 })),
  };
}
