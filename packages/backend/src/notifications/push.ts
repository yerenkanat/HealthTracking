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
// Copy generators — the Nudge Master's voice, localizable.
// Tone: warm, first-name, reassuring, never alarmist unless it's a real emergency.
// ---------------------------------------------------------------------------
export function geofenceCopy(evt: GeofenceEvent, childName: string): PushMessage {
  const arrived = evt.transition === 'enter';
  // Warm, concrete, low-anxiety. Localization layer swaps these by user.locale.
  const map: Record<string, PushMessage> = {
    'enter:School': {
      title: `${childName} is at school ✅`,
      body: `${childName} just arrived safely at School. Have a good day!`,
      category: 'geofence',
    },
    'exit:School': {
      title: `${childName} left school`,
      body: `${childName} left the School zone a moment ago. We'll let you know where they head next.`,
      category: 'geofence',
    },
    'enter:Home': {
      title: `${childName} is home 🏡`,
      body: `${childName} just arrived home safely.`,
      category: 'geofence',
    },
    'exit:Home': {
      title: `${childName} left home`,
      body: `${childName} left Home ${'just now'}. Tap to see their live location.`,
      category: 'geofence',
    },
  };
  const key = `${evt.transition === 'enter' ? 'enter' : 'exit'}:${evt.geofenceName}`;
  return (
    map[key] ?? {
      title: arrived ? `${childName} arrived at ${evt.geofenceName}` : `${childName} left ${evt.geofenceName}`,
      body: arrived
        ? `${childName} just reached ${evt.geofenceName} safely.`
        : `${childName} left ${evt.geofenceName}. Tap for live location.`,
      category: 'geofence',
    }
  );
}

export function emergencyCopy(triage: TriageResult): PushMessage {
  const top = triage.findings[0];
  return {
    title: '🚨 Urgent health alert',
    body: top?.message ?? 'A serious health reading was detected. Please open the app now.',
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
export async function sendPush(tokens: string[], msg: PushMessage): Promise<void> {
  if (tokens.length === 0) return;
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
            ? { critical: 1, name: 'emergency.caf', volume: 1.0 }
            : 'default',
          // iOS 15+: time-sensitive for arrivals, critical for medical.
          'interruption-level': isCritical ? 'critical' : 'time-sensitive',
        },
      },
      headers: { 'apns-priority': '10' },
    },
  };

  const res = await admin.messaging().sendEachForMulticast(message);
  if (res.failureCount > 0) {
    // Prune dead tokens so we stop paying to retry them (DevOps concern).
    res.responses.forEach((r, i) => {
      if (
        r.error?.code === 'messaging/registration-token-not-registered' ||
        r.error?.code === 'messaging/invalid-registration-token'
      ) {
        void pruneToken(tokens[i]);
      }
    });
  }
}

async function pruneToken(_token: string): Promise<void> {
  // DELETE FROM push_tokens WHERE token = $1  — wire to your db client.
}
