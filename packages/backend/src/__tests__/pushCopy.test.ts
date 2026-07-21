/**
 * Push copy, in the language she reads.
 *
 * These strings were English literals with a comment promising that a
 * "localization layer swaps these by user.locale". There was no such layer.
 * The app defaults to Russian and ships ru/kk/en, so every push — including
 * the medical emergency — arrived in a language most of its users had not
 * chosen.
 *
 * push.ts imports firebase-admin at module load, so only the pure copy
 * functions are exercised here; sendPush needs credentials and a network.
 */

import { describe, it, expect, vi } from 'vitest';
import type { GeofenceEvent, TriageResult } from '@fcs/shared';

// firebase-admin initializes on import and would demand credentials.
vi.mock('firebase-admin', () => ({
  default: {
    apps: [{}],
    initializeApp: () => {},
    credential: { applicationDefault: () => ({}) },
    messaging: () => ({ sendEachForMulticast: async () => ({ responses: [], successCount: 0, failureCount: 0 }) }),
  },
}));

const { geofenceCopy, emergencyCopy, toPushLocale } = await import('../notifications/push');

const ENTER: GeofenceEvent = {
  childId: 'c1',
  geofenceId: 'g1',
  geofenceName: 'Школа',
  transition: 'enter',
  at: '2026-07-21T08:00:00Z',
  source: 'gps',
};
const EXIT: GeofenceEvent = { ...ENTER, transition: 'exit' };

const TRIAGE: TriageResult = {
  severity: 'emergency',
  forceEmergencyScreen: true,
  findings: [{ code: 'PREECLAMPSIA_BP', severity: 'emergency', metric: 'bp', message: 'High blood pressure detected.' }],
} as TriageResult;

describe('choosing the language', () => {
  it('narrows a stored locale to one we have copy for', () => {
    expect(toPushLocale('ru-KZ')).toBe('ru');
    expect(toPushLocale('kk')).toBe('kk');
    expect(toPushLocale('en-US')).toBe('en');
  });

  it('falls back to Russian, which is the app default — not English', () => {
    // The old copy was English-only, so an unknown locale landing on English
    // would quietly preserve exactly the bug this replaced.
    expect(toPushLocale(null)).toBe('ru');
    expect(toPushLocale(undefined)).toBe('ru');
    expect(toPushLocale('')).toBe('ru');
    expect(toPushLocale('fr')).toBe('ru');
  });
});

describe('geofence copy', () => {
  it('speaks each language', () => {
    expect(geofenceCopy(ENTER, 'Сұлтан', 'ru').title).toContain('Сұлтан');
    expect(geofenceCopy(ENTER, 'Сұлтан', 'ru').title).toMatch(/[а-яА-Я]/);
    expect(geofenceCopy(ENTER, 'Sultan', 'en').title).toBe('Sultan arrived at Школа ✅');
    expect(geofenceCopy(ENTER, 'Сұлтан', 'kk').body).toMatch(/[а-яәғқңөұүһі]/i);
  });

  it('carries the child and the zone into every language', () => {
    for (const locale of ['ru', 'kk', 'en'] as const) {
      const m = geofenceCopy(EXIT, 'Aisha', locale);
      expect(m.title, `title for ${locale}`).toContain('Aisha');
      expect(m.body, `body for ${locale}`).toContain('Школа');
      // A placeholder that survived into the delivered text means a template
      // with no value for it — worse than a missing word, because it looks
      // like a bug to her.
      expect(m.title, `unfilled placeholder in ${locale}`).not.toMatch(/\{\w+\}/);
      expect(m.body, `unfilled placeholder in ${locale}`).not.toMatch(/\{\w+\}/);
    }
  });

  it('tells arrival apart from departure', () => {
    expect(geofenceCopy(ENTER, 'A', 'ru').title).not.toBe(geofenceCopy(EXIT, 'A', 'ru').title);
  });

  it('works for a zone the copy has never seen', () => {
    // The old version had a lookup table keyed on the ENGLISH zone names
    // "School" and "Home", so a zone called "Бабушка" fell to a generic
    // English branch. Zones are named by the user, in her language.
    const m = geofenceCopy({ ...ENTER, geofenceName: 'Бабушка' }, 'Сұлтан', 'ru');
    expect(m.body).toContain('Бабушка');
    expect(m.body).not.toMatch(/\{\w+\}/);
  });
});

describe('emergency copy', () => {
  it('is localized, including the title', () => {
    expect(emergencyCopy(TRIAGE, 'ru').title).toMatch(/[а-яА-Я]/);
    expect(emergencyCopy(TRIAGE, 'kk').title).toMatch(/[а-яәғқңөұүһі]/i);
    expect(emergencyCopy(TRIAGE, 'en').title).toBe('🚨 Urgent health alert');
  });

  it('does not put the English triage prose on her lock screen', () => {
    // The finding's message is English, written for the SERVER; the app
    // localizes by code. Using it as the push body meant a Russian user's
    // emergency notification was an English sentence.
    const ru = emergencyCopy(TRIAGE, 'ru');
    expect(ru.body).not.toContain('High blood pressure detected.');
    expect(ru.body).toMatch(/[а-яА-Я]/);
  });

  it('still carries the code, so the app can localize the detail', () => {
    expect(emergencyCopy(TRIAGE, 'ru').data?.code).toBe('PREECLAMPSIA_BP');
    expect(emergencyCopy(TRIAGE, 'ru').data?.screen).toBe('EmergencyRescue');
  });

  it('is marked critical in every language', () => {
    for (const locale of ['ru', 'kk', 'en'] as const) {
      const m = emergencyCopy(TRIAGE, locale);
      expect(m.critical, `critical for ${locale}`).toBe(true);
      expect(m.category).toBe('medical_emergency');
    }
  });

  it('says something even when triage carried no finding', () => {
    const empty = { severity: 'emergency', forceEmergencyScreen: true, findings: [] } as unknown as TriageResult;
    const m = emergencyCopy(empty, 'ru');
    expect(m.body.length).toBeGreaterThan(10);
    expect(m.data?.code).toBe('UNKNOWN');
  });
});
