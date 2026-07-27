/**
 * Public content API (`/api/v1/*`) — the pregnancy calendar, the child-development
 * calendar, and the MoH medical protocols (antenatal + vaccination), for another
 * service to read and act on. No personal data lives here: it is reference content
 * plus PERSONALISED TIMELINES derived from a date passed in the request (a due
 * date, or a child's birth date), so a consumer — e.g. a WhatsApp bot — can send
 * the right week's content on the right day.
 *
 * Registered as an encapsulated plugin so the API-key guard and the /api/v1 prefix
 * apply to exactly these routes and nothing else. When an [apiKey] is configured
 * every request must carry it as `x-api-key`; without one the API is open (dev).
 */

import type { FastifyInstance } from 'fastify';
import { pregnancyCalendar, weekContent, firstWeek, lastWeek } from '../pregnancy/weeks';
import { childDevCalendar, devWeekContent, firstDevWeek, lastDevWeek } from '../child/development';
import { antenatalProtocol } from '../antenatal/protocol';
import { vaccinationSchedule } from '../vaccination/schedule';
import {
  parseDate,
  pregnancyTimeline,
  childTimeline,
  antenatalTimeline,
  vaccinationTimeline,
  coverage,
} from '../api/personalize';

export interface PublicApiOptions {
  /** When set, every /api/v1 request must send this as the `x-api-key` header. */
  apiKey?: string;
}

const clampWeeks = (raw: unknown): number => {
  const n = Number.parseInt(String(raw ?? ''), 10);
  return Number.isFinite(n) ? Math.max(1, Math.min(20, n)) : 6;
};

export function registerPublicApiRoutes(app: FastifyInstance, opts: PublicApiOptions = {}): void {
  const requireKey = Boolean(opts.apiKey);

  app.register(
    async (api) => {
      // One guard for the whole surface. A missing/wrong key never reaches a handler.
      api.addHook('onRequest', async (req, reply) => {
        if (requireKey && req.headers['x-api-key'] !== opts.apiKey) {
          return reply.code(401).send({ error: 'invalid_api_key' });
        }
      });

      // Self-describing index — so whoever integrates can discover the surface.
      api.get('/', async () => ({
        service: 'Umay content API',
        version: 'v1',
        authRequired: requireKey,
        coverage,
        endpoints: {
          'GET /api/v1/pregnancy/weeks': 'Full pregnancy calendar (all weeks, ru+kk).',
          'GET /api/v1/pregnancy/weeks/:week': 'One gestational week (clamped to the covered range).',
          'GET /api/v1/pregnancy/timeline': 'Personalised. Params: dueDate=YYYY-MM-DD (required), from=YYYY-MM-DD (default today), weeks=1..20 (default 6). Returns currentWeek + a dated timeline.',
          'GET /api/v1/child/weeks': 'Full child-development calendar (all weeks, ru+kk).',
          'GET /api/v1/child/weeks/:week': 'One development week (clamped).',
          'GET /api/v1/child/timeline': 'Personalised. Params: birthDate=YYYY-MM-DD (required), from, weeks. Returns currentWeek + a dated timeline.',
          'GET /api/v1/protocols/antenatal': 'MoH 8-visit antenatal protocol (reference).',
          'GET /api/v1/protocols/antenatal/timeline': 'Personalised. Param: dueDate. Each visit mapped to real from/to dates.',
          'GET /api/v1/protocols/vaccination': 'Childhood immunisation schedule (reference).',
          'GET /api/v1/protocols/vaccination/timeline': 'Personalised. Params: birthDate, from. Each vaccine mapped to a due date + past/due/upcoming.',
        },
      }));

      // ---- Pregnancy calendar ----
      api.get('/pregnancy/weeks', async () => ({ version: pregnancyCalendar.version, count: pregnancyCalendar.weeks.length, first: firstWeek, last: lastWeek, weeks: pregnancyCalendar.weeks }));
      api.get('/pregnancy/weeks/:week', async (req, reply) => {
        const week = Number.parseInt((req.params as { week: string }).week, 10);
        if (!Number.isFinite(week)) return reply.code(400).send({ error: 'invalid_week' });
        const content = weekContent(week);
        return content ? { week: content } : reply.code(404).send({ error: 'not_found' });
      });
      api.get('/pregnancy/timeline', async (req, reply) => {
        const q = req.query as Record<string, string>;
        const dueDate = parseDate(q.dueDate);
        if (!dueDate) return reply.code(400).send({ error: 'invalid_dueDate', hint: 'dueDate=YYYY-MM-DD is required' });
        const from = q.from ? parseDate(q.from) : new Date();
        if (!from) return reply.code(400).send({ error: 'invalid_from' });
        return { dueDate: q.dueDate, from: from.toISOString().slice(0, 10), version: pregnancyCalendar.version, ...pregnancyTimeline(dueDate, from, clampWeeks(q.weeks)) };
      });

      // ---- Child development ----
      api.get('/child/weeks', async () => ({ version: childDevCalendar.version, note: childDevCalendar.note, count: childDevCalendar.weeks.length, first: firstDevWeek, last: lastDevWeek, weeks: childDevCalendar.weeks }));
      api.get('/child/weeks/:week', async (req, reply) => {
        const week = Number.parseInt((req.params as { week: string }).week, 10);
        if (!Number.isFinite(week)) return reply.code(400).send({ error: 'invalid_week' });
        const content = devWeekContent(week);
        return content ? { week: content, note: childDevCalendar.note } : reply.code(404).send({ error: 'not_found' });
      });
      api.get('/child/timeline', async (req, reply) => {
        const q = req.query as Record<string, string>;
        const birthDate = parseDate(q.birthDate);
        if (!birthDate) return reply.code(400).send({ error: 'invalid_birthDate', hint: 'birthDate=YYYY-MM-DD is required' });
        const from = q.from ? parseDate(q.from) : new Date();
        if (!from) return reply.code(400).send({ error: 'invalid_from' });
        return { birthDate: q.birthDate, from: from.toISOString().slice(0, 10), version: childDevCalendar.version, note: childDevCalendar.note, ...childTimeline(birthDate, from, clampWeeks(q.weeks)) };
      });

      // ---- Medical protocols ----
      api.get('/protocols/antenatal', async () => antenatalProtocol);
      api.get('/protocols/antenatal/timeline', async (req, reply) => {
        const q = req.query as Record<string, string>;
        const dueDate = parseDate(q.dueDate);
        if (!dueDate) return reply.code(400).send({ error: 'invalid_dueDate', hint: 'dueDate=YYYY-MM-DD is required' });
        return { dueDate: q.dueDate, version: antenatalProtocol.version, categories: antenatalProtocol.categories, visits: antenatalTimeline(dueDate) };
      });
      api.get('/protocols/vaccination', async () => vaccinationSchedule);
      api.get('/protocols/vaccination/timeline', async (req, reply) => {
        const q = req.query as Record<string, string>;
        const birthDate = parseDate(q.birthDate);
        if (!birthDate) return reply.code(400).send({ error: 'invalid_birthDate', hint: 'birthDate=YYYY-MM-DD is required' });
        const from = q.from ? parseDate(q.from) : new Date();
        if (!from) return reply.code(400).send({ error: 'invalid_from' });
        return { birthDate: q.birthDate, from: from.toISOString().slice(0, 10), version: vaccinationSchedule.version, vaccines: vaccinationTimeline(birthDate, from) };
      });
    },
    { prefix: '/api/v1' },
  );
}
