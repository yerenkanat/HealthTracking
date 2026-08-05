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
import type { Repository, AudioLocale, ShopProduct } from '../db/repository';
import { pregnancyCalendar, weekContent, firstWeek, lastWeek } from '../pregnancy/weeks';
import { childDevCalendar, devWeekContent, firstDevWeek, lastDevWeek } from '../child/development';
import { antenatalProtocol } from '../antenatal/protocol';
import { vaccinationSchedule } from '../vaccination/schedule';
import {
  parseDate,
  pregnancyTimeline,
  childTimeline,
  pregnancyDayOn,
  childDayOn,
  antenatalTimeline,
  vaccinationTimeline,
  coverage,
} from '../api/personalize';

export interface PublicApiOptions {
  /** When set, every /api/v1 request must send this as the `x-api-key` header. */
  apiKey?: string;
}

const toLocale = (lang: unknown): AudioLocale => (lang === 'kk' || lang === 'kz' ? 'kk' : 'ru');

const clampWeeks = (raw: unknown): number => {
  const n = Number.parseInt(String(raw ?? ''), 10);
  return Number.isFinite(n) ? Math.max(1, Math.min(20, n)) : 6;
};

export function registerPublicApiRoutes(app: FastifyInstance, repo: Repository, opts: PublicApiOptions = {}): void {
  const requireKey = Boolean(opts.apiKey);

  // Does this (track, day, locale) have an uploaded clip? Metadata lookup, no bytes.
  const audioUrlFor = async (track: 'pregnancy' | 'child', day: number, locale: AudioLocale): Promise<string | null> => {
    const has = (await repo.listDailyAudio(track)).some((a) => a.day === day && a.locale === locale);
    return has ? `/audio/${track}/${day}/${locale}` : null;
  };

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
        service: 'Ana-Bala content API',
        version: 'v1',
        docs: '/api-docs',
        authRequired: requireKey,
        // Static calendar/protocol ranges + live counts (daily-audio clips per
        // track, shop products) so the index reflects every content type.
        coverage: {
          ...coverage,
          audio: {
            pregnancy: (await repo.listDailyAudio('pregnancy')).length,
            child: (await repo.listDailyAudio('child')).length,
          },
          shopProducts: (await repo.shopProducts()).length,
        },
        endpoints: {
          'GET /api/v1/pregnancy/weeks': 'Full pregnancy calendar (all weeks, ru+kk).',
          'GET /api/v1/pregnancy/weeks/:week': 'One gestational week (clamped to the covered range).',
          'GET /api/v1/pregnancy/timeline': 'Personalised. Params: dueDate=YYYY-MM-DD (required), from=YYYY-MM-DD (default today), weeks=1..20 (default 6). Returns currentWeek + a dated timeline.',
          'GET /api/v1/pregnancy/today': "Personalised for one day. Params: dueDate (required), from, lang=ru|kk. Returns the gestational day, its week content, and the day's audioUrl (or null).",
          'GET /api/v1/child/today': "Personalised. Params: birthDate (required), from, lang. Returns the child's day, week content, and the day's audioUrl.",
          'GET /api/v1/audio/:track': 'Daily-audio coverage for a track (which days have a clip). Clips stream from /audio/:track/:day/:locale.',
          'GET /api/v1/child/weeks': 'Full child-development calendar (all weeks, ru+kk).',
          'GET /api/v1/child/weeks/:week': 'One development week (clamped).',
          'GET /api/v1/child/timeline': 'Personalised. Params: birthDate=YYYY-MM-DD (required), from, weeks. Returns currentWeek + a dated timeline.',
          'GET /api/v1/protocols/antenatal': 'MoH 8-visit antenatal protocol (reference).',
          'GET /api/v1/protocols/antenatal/timeline': 'Personalised. Param: dueDate. Each visit mapped to real from/to dates.',
          'GET /api/v1/protocols/vaccination': 'Childhood immunisation schedule (reference).',
          'GET /api/v1/protocols/vaccination/timeline': 'Personalised. Params: birthDate, from. Each vaccine mapped to a due date + past/due/upcoming.',
          'GET /api/v1/shop/products': 'Shop catalogue — the smart watch and child tracker, with price and colour/stock, for storefronts and bots.',
          'GET /api/v1/shop/products/:id': 'One product by id (watch | tracker).',
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
      // What to send TODAY: the gestational day, its week's content, and the day's
      // audio clip if one is uploaded. Ideal for a daily WhatsApp push.
      api.get('/pregnancy/today', async (req, reply) => {
        const q = req.query as Record<string, string>;
        const dueDate = parseDate(q.dueDate);
        if (!dueDate) return reply.code(400).send({ error: 'invalid_dueDate', hint: 'dueDate=YYYY-MM-DD is required' });
        const from = q.from ? parseDate(q.from) : new Date();
        if (!from) return reply.code(400).send({ error: 'invalid_from' });
        const day = pregnancyDayOn(dueDate, from);
        const week = Math.min(lastWeek, Math.max(firstWeek, Math.ceil(day / 7)));
        const locale = toLocale(q.lang);
        return { dueDate: q.dueDate, from: from.toISOString().slice(0, 10), day, week, locale, content: weekContent(week), audioUrl: await audioUrlFor('pregnancy', day, locale) };
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
      api.get('/child/today', async (req, reply) => {
        const q = req.query as Record<string, string>;
        const birthDate = parseDate(q.birthDate);
        if (!birthDate) return reply.code(400).send({ error: 'invalid_birthDate', hint: 'birthDate=YYYY-MM-DD is required' });
        const from = q.from ? parseDate(q.from) : new Date();
        if (!from) return reply.code(400).send({ error: 'invalid_from' });
        const day = childDayOn(birthDate, from);
        const week = Math.min(lastDevWeek, Math.max(firstDevWeek, Math.ceil(day / 7)));
        const locale = toLocale(q.lang);
        return { birthDate: q.birthDate, from: from.toISOString().slice(0, 10), day, week, locale, content: devWeekContent(week), note: childDevCalendar.note, audioUrl: await audioUrlFor('child', day, locale) };
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

      // Daily audio coverage — which days of a track have an uploaded clip, so a
      // consumer can preload. The clips themselves stream from /audio/:track/:day/:locale.
      api.get('/audio/:track', async (req, reply) => {
        const track = (req.params as { track: string }).track;
        if (track !== 'pregnancy' && track !== 'child') return reply.code(400).send({ error: 'invalid_track' });
        const audio = (await repo.listDailyAudio(track)).map((a) => ({ day: a.day, locale: a.locale, title: a.title, url: `/audio/${track}/${a.day}/${a.locale}` }));
        return { track, count: audio.length, audio };
      });

      // ---- Shop catalogue ----
      // The public goods — the smart watch and the child tracker — with price and
      // colour/stock, so a storefront or bot can list them and check availability.
      // Same live data the shop landing pages read; price in tiyn and in tenge.
      // A bundle holds no stock of its own: it is available exactly while every
      // part it is made of is. Reading `inStock` off its (empty) colour list
      // would report the комплект as permanently sold out.
      const shapeProduct = (p: ShopProduct, all: ShopProduct[]) => ({
        id: p.id,
        name: p.name,
        priceMinor: p.priceMinor,
        priceTenge: Math.round(p.priceMinor / 100),
        kind: p.kind,
        inStock: p.kind === 'bundle'
          ? p.parts.length > 0 && p.parts.every((part) => {
            const src = all.find((x) => x.id === part.partId);
            return !!src && src.variants.some((v) => v.stock >= part.qty);
          })
          : p.variants.some((v) => v.stock > 0),
        colours: p.variants.map((v) => ({ id: v.id, color: v.color, colorHex: v.colorHex, stock: v.stock })),
        // Which products a buyer picks a colour of. Empty for a simple product.
        parts: p.parts,
      });
      api.get('/shop/products', async () => {
        const products = await repo.shopProducts();
        return { currency: 'KZT', count: products.length, products: products.map((p) => shapeProduct(p, products)) };
      });
      api.get('/shop/products/:id', async (req, reply) => {
        const id = (req.params as { id: string }).id;
        const products = await repo.shopProducts();
        const product = products.find((p) => p.id === id);
        return product ? shapeProduct(product, products) : reply.code(404).send({ error: 'not_found' });
      });
    },
    { prefix: '/api/v1' },
  );
}
