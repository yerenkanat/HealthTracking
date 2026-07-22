/**
 * Antenatal protocol — the Kazakhstan MOH 8-visit schedule, loaded from the
 * SHARED contract (packages/contract/antenatal_protocol.json), the same file the
 * Dart app asserts against and the admin panel renders. One source of truth, so
 * the app, the API and the back-office cannot tell a mother three schedules.
 *
 * Exposed at GET /antenatal/protocol (public reference data) and used to derive a
 * mother's current visit from her gestational week for the admin patient view.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export interface AntenatalItem {
  id: string;
  category: 'counsel' | 'exam' | 'lab' | 'imaging' | 'prophylaxis';
  risk: boolean;
  ru: string;
}
export interface AntenatalVisit {
  number: number;
  fromWeek: number;
  toWeek: number;
  items: AntenatalItem[];
}
export interface AntenatalWindow {
  id: string;
  fromWeek: number;
  toWeek: number;
  risk: boolean;
  ru: string;
}
export interface AntenatalProtocol {
  version: number;
  categories: Record<string, string>;
  visits: AntenatalVisit[];
  windows: AntenatalWindow[];
}

const CONTRACT_PATH = fileURLToPath(
  new URL('../../../contract/antenatal_protocol.json', import.meta.url),
);

/** The parsed protocol, read once at module load. */
export const antenatalProtocol: AntenatalProtocol = JSON.parse(
  readFileSync(CONTRACT_PATH, 'utf8'),
);

/** The visit whose window contains [week], or null between visits. */
export function visitAtWeek(week: number): AntenatalVisit | null {
  return antenatalProtocol.visits.find((v) => week >= v.fromWeek && week <= v.toWeek) ?? null;
}

/** The next visit strictly after [week], or null once the last has passed. */
export function nextVisitAfter(week: number): AntenatalVisit | null {
  return antenatalProtocol.visits.find((v) => v.fromWeek > week) ?? null;
}

/**
 * The visit due now (window contains [week]) or, failing that, the next one.
 * Null only once week is past the final window — i.e. term has arrived. Mirrors
 * the Dart `currentOrNextVisit`.
 */
export function currentOrNextVisit(week: number): AntenatalVisit | null {
  return visitAtWeek(week) ?? nextVisitAfter(week);
}

/** The screening windows open at [week], in gestational order. */
export function windowsOpenAt(week: number): AntenatalWindow[] {
  return antenatalProtocol.windows.filter((w) => week >= w.fromWeek && week <= w.toWeek);
}

/**
 * A compact per-mother status for the admin patient view: which visit is due or
 * next at her gestational [week], and whether it is due now. Null week (unknown
 * gestation) yields null.
 */
export function antenatalStatusForWeek(
  week: number | null,
): { visitNumber: number; total: number; dueNow: boolean; weekLabel: string } | null {
  if (week == null || week < 0) return null;
  const total = antenatalProtocol.visits.length;
  const due = visitAtWeek(week);
  const lead = currentOrNextVisit(week);
  if (lead == null) return { visitNumber: total, total, dueNow: false, weekLabel: `${week} нед.` };
  return {
    visitNumber: lead.number,
    total,
    dueNow: due != null,
    weekLabel: lead.fromWeek === lead.toWeek ? `${lead.fromWeek} нед.` : `${lead.fromWeek}–${lead.toWeek} нед.`,
  };
}
