/**
 * Push notification engine (FCM + APNS) with behavioral-science copy.
 * Specialists: Nudge & Behavioral Master (copy), Backend Engineer (delivery),
 * Localization Specialist (warm CIS/Central-Asian family tone), Growth Hacker
 * (shareable milestone nudges).
 *
 * Uses firebase-admin for FCM (Android) and APNS-over-FCM or node-apn for iOS.
 * Here we route everything through firebase-admin's multicast for simplicity;
 * high-priority medical alerts set the interruption level so they bypass DND.
 */

import admin from 'firebase-admin';
import type { GeofenceEvent, TriageResult } from '@fcs/shared';

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
}

export type PushCategory = 'geofence' | 'medical_emergency' | 'nudge' | 'milestone';

interface PushMessage {
  title: string;
  body: string;
  category: PushCategory;
  data?: Record<string, string>;
  /** medical_emergency → critical: bypasses Do-Not-Disturb, plays alarm sound. */
  critical?: boolean;
}

// ---------------------------------------------------------------------------
// Copy generators — the Nudge Master's voice, in the language she reads.
// Tone: warm, first-name, reassuring, never alarmist unless it's a real emergency.
//
// These used to be English string literals with a comment promising that a
// "localization layer swaps these by user.locale". There was no such layer. The
// app defaults to Russian and ships ru/kk/en, so every push — including the
// medical emergency — arrived in a language most of its users had not chosen.
// ---------------------------------------------------------------------------

export type PushLocale = 'ru' | 'kk' | 'en';

/// Narrow a stored locale ("ru-KZ", "kk", null) to one we have copy for.
/// Russian is the fallback because it is the app's own default, not English.
export function toPushLocale(raw: string | null | undefined): PushLocale {
  const s = (raw ?? '').toLowerCase();
  if (s.startsWith('kk')) return 'kk';
  if (s.startsWith('en')) return 'en';
  return 'ru';
}

type Copy = Record<PushLocale, string>;
const pick = (c: Copy, l: PushLocale) => c[l];

const ARRIVED_TITLE: Copy = {
  ru: '{name} на месте: {zone} ✅',
  kk: '{name} орнында: {zone} ✅',
  en: '{name} arrived at {zone} ✅',
};
const ARRIVED_BODY: Copy = {
  ru: '{name} только что благополучно добрался(-лась) до места «{zone}».',
  kk: '{name} «{zone}» орнына аман-есен жетті.',
  en: '{name} just reached {zone} safely.',
};
const LEFT_TITLE: Copy = {
  ru: '{name} покинул(а) зону «{zone}»',
  kk: '{name} «{zone}» аймағынан шықты',
  en: '{name} left {zone}',
};
const LEFT_BODY: Copy = {
  ru: '{name} вышел(-ла) из зоны «{zone}». Нажмите, чтобы посмотреть, где он(а) сейчас.',
  kk: '{name} «{zone}» аймағынан шықты. Қазір қайда екенін көру үшін басыңыз.',
  en: '{name} left {zone}. Tap to see their live location.',
};
const EMERGENCY_TITLE: Copy = {
  ru: '🚨 Срочное предупреждение о здоровье',
  kk: '🚨 Денсаулық туралы шұғыл ескерту',
  en: '🚨 Urgent health alert',
};
const EMERGENCY_BODY: Copy = {
  ru: 'Обнаружен серьёзный показатель. Пожалуйста, откройте приложение.',
  kk: 'Елеулі көрсеткіш анықталды. Өтінеміз, қосымшаны ашыңыз.',
  en: 'A serious health reading was detected. Please open the app now.',
};

// Frame 43 — an operator answered her. This is the notification the in-app
// support thread cannot exist without: a desk that writes into a screen she has
// no reason to reopen is a desk that never replied. Deliberately NOT critical —
// a support answer at 03:00 must not break Do Not Disturb, and red and the
// alarm sound belong to SOS alone.
const SUPPORT_TITLE: Copy = {
  ru: 'Поддержка ответила',
  kk: 'Қолдау жауап берді',
  en: 'Support replied',
};
const SUPPORT_SUBJECT: Copy = {
  ru: 'Ответ на «{subject}»',
  kk: '«{subject}» бойынша жауап',
  en: 'A reply about “{subject}”',
};

const fill = (tpl: string, vars: Record<string, string>) =>
  tpl.replace(/\{(\w+)\}/g, (_, k) => vars[k] ?? `{${k}}`);

export function geofenceCopy(
  evt: GeofenceEvent,
  childName: string,
  locale: PushLocale = 'ru',
): PushMessage {
  const arrived = evt.transition === 'enter';
  const vars = { name: childName, zone: evt.geofenceName };
  return {
    title: fill(pick(arrived ? ARRIVED_TITLE : LEFT_TITLE, locale), vars),
    body: fill(pick(arrived ? ARRIVED_BODY : LEFT_BODY, locale), vars),
    category: 'geofence',
  };
}

/**
 * «Поддержка ответила» — frame 43.
 *
 * The BODY is the operator's own words, not a summary. She should be able to
 * read a short answer («заказ уже в пути, завтра до 18:00») from the lock
 * screen without opening anything; a notification saying only that a reply
 * exists costs her a trip into the app to learn one sentence. Long answers are
 * cut rather than wrapped, because a lock-screen banner truncates anyway and
 * the app carries the whole thread.
 *
 * The subject travels as the TITLE's second line so a woman with two open
 * tickets knows which one this is — the commonest way a support thread stalls.
 */
export function supportReplyCopy(
  subject: string,
  body: string,
  locale: PushLocale = 'ru',
  ticketId?: string,
): PushMessage {
  const line = body.trim().replace(/\s+/g, ' ');
  return {
    title: pick(SUPPORT_TITLE, locale),
    body: line.length > 160 ? `${line.slice(0, 159)}…` : line,
    category: 'nudge',
    data: {
      screen: 'SupportThread',
      subject: fill(pick(SUPPORT_SUBJECT, locale), { subject }),
      ...(ticketId ? { ticketId } : {}),
    },
  };
}

/**
 * A рассылка — frame 06.
 *
 * There are no COPY templates here, and that is the point: the words are the
 * ones a person wrote in the back office, in the language she reads, and this
 * function only decides how they are delivered. A template would mean the panel
 * showed one sentence and the phone displayed another.
 *
 * Deliberately NOT critical and category `nudge`: marketing must never break
 * Do Not Disturb. Red, the alarm sound and the DND bypass belong to an SOS
 * alone, and the day they are shared with an announcement is the day people
 * start silencing the app.
 *
 * `screen` sends a tap to the notification centre, where the same message is
 * already waiting from GET /announcements — so the notification and the app
 * agree even if the push arrives twice or not at all.
 */
export function announcementCopy(
  title: string, body: string, broadcastId?: string,
): PushMessage {
  const line = body.trim().replace(/\s+/g, ' ');
  return {
    title: title.trim(),
    // Cut rather than wrapped: a lock-screen banner truncates anyway, and the
    // whole text is in the centre.
    body: line.length > 160 ? `${line.slice(0, 159)}…` : line,
    category: 'nudge',
    data: {
      screen: 'NotificationCentre',
      ...(broadcastId ? { broadcastId } : {}),
    },
  };
}

export function emergencyCopy(triage: TriageResult, locale: PushLocale = 'ru'): PushMessage {
  const top = triage.findings[0];
  return {
    title: pick(EMERGENCY_TITLE, locale),
    // The finding's own message is English prose from the shared triage module;
    // the APP localizes by CODE. So the code travels in `data` and the body
    // stays a sentence she can read — the phone screen is not the place to
    // discover that the alert is in the wrong language.
    body: pick(EMERGENCY_BODY, locale),
    category: 'medical_emergency',
    critical: true,
    data: {
      screen: 'EmergencyRescue',
      code: top?.code ?? 'UNKNOWN',
    },
  };
}

// ---------------------------------------------------------------------------
// Delivery
// ---------------------------------------------------------------------------
export interface PushResult {
  sent: number;
  failed: number;
  /** Tokens FCM says are dead; the caller should forget them. */
  dead: string[];
  /** Set when the whole send failed rather than individual tokens. */
  error?: string;
}

/**
 * Deliver, and REPORT rather than throw.
 *
 * This used to let a failure propagate. The emergency path is
 * ingestTelemetry → sendEmergencyPush → here, inside handleIngestBatch's
 * per-item try/catch — so a push that failed marked the reading `rejected`
 * even though it had already been stored and counted, and the caller received
 * a summary that contradicted itself. Meanwhile nothing recorded that the most
 * important notification in the product had not gone out.
 */
export async function sendPush(tokens: string[], msg: PushMessage): Promise<PushResult> {
  if (tokens.length === 0) {
    // Not an error, but not nothing either: an emergency with nowhere to go is
    // the difference between "alerted" and "believed she was alerted".
    return { sent: 0, failed: 0, dead: [], error: 'no_tokens' };
  }
  const isCritical = msg.category === 'medical_emergency' || msg.critical;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: { title: msg.title, body: msg.body },
    data: { category: msg.category, ...(msg.data ?? {}) },
    android: {
      priority: 'high',
      notification: {
        channelId: isCritical ? 'medical_critical' : 'default',
        // Critical channel is registered with IMPORTANCE_HIGH + bypassDnd on the client.
        sound: isCritical ? 'emergency' : 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: isCritical
            // `critical` is a boolean in the Admin SDK, which serializes it to
            // the APNs wire value itself. Passing the raw 1 typechecks as a
            // number and is rejected — on the one path that must break a
            // medical alert through Do Not Disturb.
            ? { critical: true, name: 'emergency.caf', volume: 1.0 }
            : 'default',
          // iOS 15+: time-sensitive for arrivals, critical for medical.
          'interruption-level': isCritical ? 'critical' : 'time-sensitive',
        },
      },
      headers: { 'apns-priority': '10' },
    },
  };

  let res: admin.messaging.BatchResponse;
  try {
    res = await admin.messaging().sendEachForMulticast(message);
  } catch (e) {
    return {
      sent: 0,
      failed: tokens.length,
      dead: [],
      error: e instanceof Error ? e.message : String(e),
    };
  }

  // Tokens FCM has told us are dead — a reinstall, an uninstall, a restore onto
  // a new phone. They are RETURNED rather than deleted here: this module knows
  // nothing about the database, and the previous version's pruneToken() was an
  // empty function with a comment promising it would be wired up. It never was,
  // so dead tokens accumulated for ever and every push to them failed quietly
  // inside an otherwise successful multicast.
  const dead: string[] = [];
  res.responses.forEach((r, i) => {
    if (
      r.error?.code === 'messaging/registration-token-not-registered' ||
      r.error?.code === 'messaging/invalid-registration-token'
    ) {
      dead.push(tokens[i]);
    }
  });

  return { sent: res.successCount, failed: res.failureCount, dead };
}
