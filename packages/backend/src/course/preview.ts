/**
 * Screen 34 — «Курс · без комплекта».
 *
 * docs/CLAUDE-app-design.md: «обложка → описание → список: урок 1 бесплатно,
 * дальше замки → карточка цены → «Заказать комплект в WhatsApp» → «Купить
 * только курс».»
 *
 * The locked screen used to be one card saying the course exists. That sells
 * nothing: «двенадцать уроков» is an assertion, whereas the actual titles are
 * evidence — she can see the one about sleep, the one about the first month,
 * and the one she needs THIS week.
 *
 * So the list is shown to somebody who has not bought. What is NOT shown is
 * the video: a locked lesson comes back with no URL at all, because a paywall
 * that ships the thing it is paywalling is a decoration. Stripping it here, in
 * one function, is what makes that checkable.
 */

import type { CourseLesson } from '../db/repository';

/**
 * How many lessons play without buying anything.
 *
 * One. Enough to judge whether the teaching is any good — which is the only
 * question a preview can honestly answer — and not enough to be the course.
 */
export const FREE_LESSONS = 1;

/** A lesson as an unentitled viewer sees it. */
export interface PreviewLesson {
  id: string;
  course: string;
  titleRu: string;
  titleKk: string | null;
  summaryRu: string | null;
  summaryKk: string | null;
  sort: number;
  /** Playable without buying. */
  free: boolean;
  /**
   * Present ONLY on a free lesson. Absent — not empty-string, absent — on
   * everything else, so a client cannot accidentally treat '' as a URL and a
   * reader of the JSON can see at a glance that nothing leaked.
   */
  youtubeUrl?: string;
}

/**
 * The list for somebody who has not bought the course.
 *
 * Ordered by `sort` here rather than trusting the caller: "the first lesson"
 * has to mean the first one SHE sees, and a differently-ordered array would
 * unlock whichever happened to be at index 0.
 */
export function previewLessons(
  lessons: CourseLesson[],
  freeCount = FREE_LESSONS,
): PreviewLesson[] {
  return [...lessons]
    .sort((a, b) => a.sort - b.sort || a.createdAt.localeCompare(b.createdAt))
    .map((l, i) => {
      const free = i < freeCount;
      return {
        id: l.id,
        course: l.course,
        titleRu: l.titleRu,
        titleKk: l.titleKk,
        summaryRu: l.summaryRu,
        summaryKk: l.summaryKk,
        sort: l.sort,
        free,
        ...(free ? { youtubeUrl: l.youtubeUrl } : {}),
      };
    });
}

/**
 * May this lesson be watched without an entitlement?
 *
 * The guard the PLAYER route needs. Asking "is it the first one" at the point
 * of play, from the same ordering, is what stops a client that kept an id from
 * an older response playing a lesson that has since been locked.
 */
export function isFreeLesson(
  lessons: CourseLesson[],
  lessonId: string,
  freeCount = FREE_LESSONS,
): boolean {
  return previewLessons(lessons, freeCount).some((l) => l.free && l.id === lessonId);
}
