/**
 * Personalisation for the public content API — turns a single date (a due date,
 * or a child's birth date) into a week-by-week timeline another service can
 * schedule against (e.g. a WhatsApp bot sending "this week" content).
 *
 * Everything here is PURE: every function takes the reference "today" (or "from")
 * as an argument rather than reading the clock, so the timelines are deterministic
 * and unit-testable. The routes supply the clock.
 *
 * Obstetric convention: EDD (due date) = LMP + 280 days = 40w0d. So gestational
 * age today, in completed weeks, is floor((280 − daysUntilDue) / 7), and
 * gestational week W begins at LMP + 7·W = dueDate − (280 − 7·W) days.
 */

import { pregnancyCalendar, weekContent, firstWeek, lastWeek, type PregnancyWeek } from '../pregnancy/weeks';
import { childDevCalendar, devWeekContent, firstDevWeek, lastDevWeek, type ChildDevWeek } from '../child/development';
import { antenatalProtocol, type AntenatalVisit } from '../antenatal/protocol';
import { vaccinationSchedule, type Vaccine } from '../vaccination/schedule';

const DAY_MS = 86_400_000;
const GESTATION_DAYS = 280; // 40 weeks

/** Parse a strict YYYY-MM-DD as UTC midnight, or null if it is not a real date. */
export function parseDate(s: unknown): Date | null {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const d = new Date(`${s}T00:00:00Z`);
  return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s ? null : d;
}

/** Format a Date as YYYY-MM-DD (UTC). */
export function fmtDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

const addDays = (d: Date, n: number): Date => new Date(d.getTime() + n * DAY_MS);
const diffDays = (a: Date, b: Date): number => Math.round((a.getTime() - b.getTime()) / DAY_MS);
const clamp = (n: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, n));

/** Add [n] whole months to a UTC date, clamping the day to the target month. */
function addMonths(d: Date, n: number): Date {
  const y = d.getUTCFullYear();
  const m = d.getUTCMonth() + n;
  const day = d.getUTCDate();
  const target = new Date(Date.UTC(y, m, 1));
  const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(day, lastDay));
  return target;
}

// ---- Pregnancy ----

/** Gestational week (completed weeks, clamped to the calendar) on [today]. */
export function pregnancyWeekOn(dueDate: Date, today: Date): number {
  const gestDays = GESTATION_DAYS - diffDays(dueDate, today);
  return clamp(Math.floor(gestDays / 7), firstWeek, lastWeek);
}

/** Gestational day (1..280, clamped) on [today] — for daily audio. */
export function pregnancyDayOn(dueDate: Date, today: Date): number {
  return clamp(GESTATION_DAYS - diffDays(dueDate, today), 1, GESTATION_DAYS);
}

/** The calendar date on which gestational week [w] begins for this pregnancy. */
function pregnancyWeekStart(dueDate: Date, w: number): Date {
  return addDays(dueDate, -(GESTATION_DAYS - 7 * w));
}

export interface PregnancyTimelineEntry {
  week: number;
  weekStart: string; // YYYY-MM-DD — when to send this week's content
  content: PregnancyWeek | null;
}

/**
 * Current week + the next [weeks−1], each with the date it begins, for
 * scheduling.
 *
 * [calendar] is the SERVED calendar — contract plus whatever the back office
 * has edited (pregnancy/served.ts). Optional so this module stays pure and its
 * tests need no repository; when it is omitted the compiled-in contract is
 * used, which is what every caller did before week 14b made the text editable.
 * A caller that has the served calendar to hand should pass it: a partner
 * scheduling messages off this timeline and a mother reading the app must not
 * be told different things about week 22.
 */
export function pregnancyTimeline(
  dueDate: Date,
  from: Date,
  weeks: number,
  calendar?: { weeks: PregnancyWeek[] },
): { currentWeek: number; timeline: PregnancyTimelineEntry[] } {
  const lookup = (w: number): PregnancyWeek | null =>
    calendar ? calendar.weeks.find((x) => x.week === w) ?? null : weekContent(w);
  const currentWeek = pregnancyWeekOn(dueDate, from);
  const end = Math.min(currentWeek + weeks - 1, lastWeek);
  const timeline: PregnancyTimelineEntry[] = [];
  for (let w = currentWeek; w <= end; w++) {
    timeline.push({ week: w, weekStart: fmtDate(pregnancyWeekStart(dueDate, w)), content: lookup(w) });
  }
  return { currentWeek, timeline };
}

// ---- Child development ----

/** Child age in whole weeks (clamped to the calendar) on [today]. */
export function childWeekOn(birthDate: Date, today: Date): number {
  return clamp(Math.floor(diffDays(today, birthDate) / 7), firstDevWeek, lastDevWeek);
}

/** Child age in days (1..400, clamped; day 1 = birth day) on [today] — daily audio. */
export function childDayOn(birthDate: Date, today: Date): number {
  return clamp(diffDays(today, birthDate) + 1, 1, 400);
}

export interface ChildTimelineEntry {
  week: number;
  weekStart: string;
  content: ChildDevWeek | null;
}

export function childTimeline(birthDate: Date, from: Date, weeks: number): { currentWeek: number; timeline: ChildTimelineEntry[] } {
  const currentWeek = childWeekOn(birthDate, from);
  const end = Math.min(currentWeek + weeks - 1, lastDevWeek);
  const timeline: ChildTimelineEntry[] = [];
  for (let w = currentWeek; w <= end; w++) {
    timeline.push({ week: w, weekStart: fmtDate(addDays(birthDate, 7 * w)), content: devWeekContent(w) });
  }
  return { currentWeek, timeline };
}

// ---- Antenatal protocol (personalised visit windows) ----

export interface AntenatalVisitWindow {
  number: number;
  fromWeek: number;
  toWeek: number;
  fromDate: string; // when this visit window opens for this pregnancy
  toDate: string; // when it closes
  items: AntenatalVisit['items'];
}

/** Each protocol visit mapped onto real dates for a given due date. */
export function antenatalTimeline(dueDate: Date): AntenatalVisitWindow[] {
  return antenatalProtocol.visits.map((v) => ({
    number: v.number,
    fromWeek: v.fromWeek,
    toWeek: v.toWeek,
    fromDate: fmtDate(pregnancyWeekStart(dueDate, v.fromWeek)),
    // the window covers through the END of toWeek, i.e. the day before (toWeek+1) begins
    toDate: fmtDate(addDays(pregnancyWeekStart(dueDate, v.toWeek + 1), -1)),
    items: v.items,
  }));
}

// ---- Vaccination schedule (personalised due dates) ----

export interface VaccineDue {
  id: string;
  atMonth: number;
  dose?: number;
  ru: string;
  dueDate: string; // birthDate + atMonth months
  status: 'past' | 'due' | 'upcoming'; // relative to [from], within the catch-up window
}

/** Every scheduled vaccine mapped to a real due date for a given birth date,
 * tagged past/due/upcoming relative to [from].
 *
 * [schedule] defaults to the shipped contract so every existing caller and test
 * keeps its meaning, but `/api/v1` passes the SERVED schedule — the contract
 * with the back office's edits on top. A public timeline that still answered
 * from the compiled-in file would tell an integrator one date and the app
 * another the moment anybody moved a dose. */
export function vaccinationTimeline(
  birthDate: Date,
  from: Date,
  schedule: { dueWindowMonths: number; vaccines: Vaccine[] } = vaccinationSchedule,
): VaccineDue[] {
  const windowDays = schedule.dueWindowMonths * 30;
  return schedule.vaccines
    .map((v: Vaccine) => {
      const due = addMonths(birthDate, v.atMonth);
      const ageAtDue = diffDays(from, due);
      const status: VaccineDue['status'] = ageAtDue < 0 ? 'upcoming' : ageAtDue <= windowDays ? 'due' : 'past';
      return { id: v.id, atMonth: v.atMonth, dose: v.dose, ru: v.ru, dueDate: fmtDate(due), status };
    })
    .sort((a, b) => a.dueDate.localeCompare(b.dueDate));
}

/** Ranges the calendars/protocols cover — surfaced in the API index. */
export const coverage = {
  pregnancyWeeks: { first: firstWeek, last: lastWeek, version: pregnancyCalendar.version },
  childWeeks: { first: firstDevWeek, last: lastDevWeek, version: childDevCalendar.version },
  antenatalVisits: antenatalProtocol.visits.length,
  vaccines: vaccinationSchedule.vaccines.length,
};
