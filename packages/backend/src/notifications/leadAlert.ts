/**
 * Tell staff a customer asked to be called back.
 *
 * Until now a lead landed in shop_leads and nothing happened. The only way to
 * find out was for somebody to open the admin panel and look — so a customer
 * who filled the form on a Friday evening waited until whenever that next
 * occurred to someone. For a page whose whole job is collecting callbacks,
 * that is the feature not being finished rather than a missing nicety.
 *
 * Telegram rather than email: it needs no SMTP relay, no domain reputation and
 * no spam-folder problem, staff already have it on the phones they carry, and
 * a bot token can be revoked in one tap. The transport is behind an interface
 * so a second channel can be added without touching the route.
 *
 * NOTHING here may throw into the request. A customer's callback must be
 * recorded even if every notification channel is misconfigured or down — the
 * row in the database is the commitment, the message is the convenience.
 */

import type { ShopLeadInput } from '../db/repository';

export interface LeadAlertConfig {
  telegramBotToken?: string;
  telegramChatId?: string;
}

/** What the notifier needs, kept narrow so tests do not need a repository. */
export interface LeadAlertDeps {
  /** Read fresh each time: staff can change the token in the admin panel and
   *  it must take effect without a restart. */
  loadConfig: () => Promise<LeadAlertConfig>;
  /** Injected for tests; defaults to global fetch. */
  fetchImpl?: typeof fetch;
  now?: () => Date;
  onError?: (message: string) => void;
}

const LOCALE_LABEL: Record<string, string> = { ru: 'русский', kz: 'қазақша' };

const SEND_TIMEOUT_MS = 8000;

/**
 * The message staff receive. Deliberately plain text, not Markdown or HTML:
 * a customer named `**Aigerim**` or an address with an underscore would
 * otherwise break Telegram's parser and the send would fail — losing the alert
 * for exactly the lead most worth reading.
 */
export function formatLeadMessage(lead: ShopLeadInput, at: Date): string {
  const lines = [
    'Новая заявка — Ana-Bala',
    '',
    `Имя:      ${lead.customerName}`,
    `Телефон:  ${lead.phone}`,
  ];
  if (lead.package) lines.push(`Пакет:    ${lead.package}`);
  if (lead.locale) lines.push(`Язык:     ${LOCALE_LABEL[lead.locale] ?? lead.locale}`);
  // Almaty is UTC+5 and staff read this on a phone set to local time; a UTC
  // stamp would have them working out whether a lead is ten minutes or five
  // hours old.
  lines.push(
    `Время:    ${at.toLocaleString('ru-RU', { timeZone: 'Asia/Almaty', dateStyle: 'short', timeStyle: 'short' })} (Алматы)`,
  );
  lines.push('', 'Перезвоните как можно скорее.');
  return lines.join('\n');
}

export type LeadNotifier = (lead: ShopLeadInput) => Promise<void>;

/**
 * Send a message through the saved credentials and REPORT what happened.
 *
 * Deliberately unlike the notifier above, which swallows everything: this exists
 * to put Telegram's own words ("chat not found", "Unauthorized") in front of
 * the person who just pasted the token.
 */
export async function sendTelegramTest(
  token: string,
  chatId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetchImpl(`https://api.telegram.org/bot${token.trim()}/sendMessage`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId.trim(),
        text: 'Ana-Bala: проверка связи. Сюда будут приходить заявки с сайта.',
      }),
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    });
    if (res.ok) return { ok: true };
    const body = (await res.text().catch(() => '')).slice(0, 300);
    // Telegram's description field is the useful half; fall back to the raw
    // body if it is shaped unexpectedly.
    let described = body;
    try {
      const parsed = JSON.parse(body) as { description?: string };
      if (parsed.description) described = parsed.description;
    } catch {
      /* not JSON — show what came back */
    }
    return { ok: false, error: `${res.status} ${described}` };
  } catch (err) {
    return { ok: false, error: (err as Error).message };
  }
}

export function createLeadNotifier(deps: LeadAlertDeps): LeadNotifier {
  const doFetch = deps.fetchImpl ?? fetch;
  const now = deps.now ?? (() => new Date());
  const warn = deps.onError ?? ((m: string) => console.warn(m));

  return async (lead) => {
    try {
      const cfg = await deps.loadConfig();
      const token = cfg.telegramBotToken?.trim();
      const chatId = cfg.telegramChatId?.trim();
      // Unconfigured is the normal state until staff paste a token, and it is
      // not an error worth logging on every submission.
      if (!token || !chatId) return;

      const res = await doFetch(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          text: formatLeadMessage(lead, now()),
          disable_web_page_preview: true,
        }),
        // The response to the customer has already been sent, but the request
        // is not finished until this settles. Without a bound, an unreachable
        // api.telegram.org would hold a connection open per submission.
        signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
      });
      if (!res.ok) {
        // Telegram puts the real reason in the body ("chat not found", "bot was
        // blocked"), and without it the log says only "400" — which is not
        // enough to fix a token someone pasted with a stray space.
        const detail = await res.text().catch(() => '');
        warn(`lead alert: telegram ${res.status} ${detail.slice(0, 300)}`);
      }
    } catch (err) {
      warn(`lead alert: ${(err as Error).message}`);
    }
  };
}
