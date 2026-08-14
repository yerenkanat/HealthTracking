/**
 * THE one way this server sends a push.
 *
 * Everything a delivery has to do — consult her switches, honour her quiet
 * hours IN HER TIMEZONE, forget the tokens FCM has declared dead, record what
 * happened, and say so in the log — lives here, in a module a test can hold.
 *
 * WHY A MODULE AND NOT FIVE LINES IN index.ts. The composition root is not
 * reachable from a test: productionDeps() imports pg, Redis, Anthropic and
 * firebase-admin. Left there, the gate would be code no test can execute, which
 * is precisely the shape of every "wired to nothing" defect in this repository.
 * index.ts now supplies tokens and copy and nothing else; the decision is here.
 *
 * THE INVARIANT: an SOS and a medical emergency are never held. That lives in
 * gate.ts (`categoryOf` returns null for both) rather than in this file, so
 * there is exactly one place to get it wrong — and a test that reverts it
 * watches this dispatcher start swallowing alarms.
 */

import type { HoldReason, PushKind } from './gate';
import { holdReasonFor, minuteOfDayIn } from './gate';
import type { NotificationPrefsRow, PushDeliveryRecord } from '../db/repository';

/** What sendPush() answers. Structural, so this module never imports FCM. */
export interface PushSendResult {
  sent: number;
  failed: number;
  dead: string[];
  error?: string;
}

/** What a delivery attempt did — returned so callers can report honestly. */
export interface DeliveryOutcome {
  kind: string;
  /** Set when the gate held it; null when we tried. */
  held: HoldReason | null;
  /** Phones FCM accepted it for. Zero when held. */
  sent: number;
  failed: number;
  /** Dead tokens removed on this attempt. */
  dead: number;
  error: string | null;
}

/** The slice of the repository a dispatcher needs — nothing wider. */
export interface DispatchRepo {
  getNotificationPrefs(userId: string): Promise<NotificationPrefsRow>;
  deletePushToken(token: string): Promise<void>;
  recordPushDelivery(row: PushDeliveryRecord): Promise<void>;
}

/**
 * Generic in the message type so this module never imports the FCM copy
 * builders — it decides WHETHER, and the copy modules decide WHAT.
 */
export interface DispatchDeps<M> {
  repo: DispatchRepo;
  /** The real `sendPush` from ./push, or a fake. */
  send: (tokens: string[], msg: M) => Promise<PushSendResult>;
  /** Overridable for tests; the whole point of quiet hours is WHEN. */
  now?: () => Date;
  warn?: (line: string) => void;
}

export interface PushDispatcher<M> {
  /**
   * Send [msg] to [tokens] on behalf of [userId], subject to her preferences.
   *
   * [userId] may be null for a send with no single owner; the gate is then
   * skipped, because there is nobody whose switches could apply. Every caller
   * in this product has one, and passing null is a deliberate statement rather
   * than a shrug.
   */
  deliver(
    kind: PushKind | string,
    userId: string | null,
    tokens: string[],
    msg: M,
  ): Promise<DeliveryOutcome>;
}

export function createPushDispatch<M>(deps: DispatchDeps<M>): PushDispatcher<M> {
  const now = deps.now ?? (() => new Date());
  const warn = deps.warn ?? (() => {});

  /**
   * Write the ledger row, and never let that failure become a push failure.
   *
   * An unmigrated database (047 not applied) must not stop notifications. The
   * catch is loud in the log and silent to the caller, which is the correct way
   * round: losing the record of an emergency push is bad, not sending it is
   * worse.
   */
  async function record(row: PushDeliveryRecord): Promise<void> {
    try {
      await deps.repo.recordPushDelivery(row);
    } catch (e) {
      warn(`push(${row.kind}): delivery not recorded — ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  /**
   * Should this one go? Null = yes.
   *
   * A repository that cannot answer means SEND. Preferences we cannot read are
   * not preferences to mute by: the failure mode of the opposite choice is a
   * database blip silencing everybody's notifications at once, and nobody
   * finding out for a week.
   */
  async function holdFor(kind: string, userId: string): Promise<HoldReason | null> {
    let prefs: NotificationPrefsRow;
    try {
      prefs = await deps.repo.getNotificationPrefs(userId);
    } catch (e) {
      warn(`push(${kind}): preferences unreadable, sending anyway — ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }
    // HER minute of HER day. The server's clock is not an input.
    return holdReasonFor(kind, prefs, minuteOfDayIn(prefs.timezone, now()));
  }

  return {
    async deliver(kind, userId, tokens, msg) {
      if (userId) {
        const held = await holdFor(kind, userId);
        if (held) {
          await record({ userId, kind, sent: 0, failed: 0, dead: 0, heldReason: held, error: null });
          // Said out loud at info level, not swallowed: «ей не пришло» must be
          // answerable from the log as well as from the table.
          warn(`push(${kind}): held for ${userId} — ${held}`);
          return { kind, held, sent: 0, failed: 0, dead: 0, error: null };
        }
      }

      const res = await deps.send(tokens, msg);

      // Forget the tokens FCM told us are dead — a reinstall, an uninstall, a
      // restore onto a new phone. Left behind, they accumulate for ever and
      // swallow every future push inside an otherwise successful multicast.
      for (const token of res.dead) {
        await deps.repo.deletePushToken(token).catch(() => {});
      }

      await record({
        userId,
        kind,
        sent: res.sent,
        failed: res.failed,
        dead: res.dead.length,
        heldReason: null,
        error: res.error ?? null,
      });

      if (res.error || res.failed > 0) {
        warn(
          `push(${kind}): ${res.sent} delivered, ${res.failed} failed` +
            (res.error ? ` — ${res.error}` : '') +
            (res.dead.length ? `, ${res.dead.length} dead token(s) removed` : ''),
        );
      }
      return {
        kind,
        held: null,
        sent: res.sent,
        failed: res.failed,
        dead: res.dead.length,
        error: res.error ?? null,
      };
    },
  };
}
