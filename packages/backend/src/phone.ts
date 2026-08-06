/**
 * One phone number, one written form.
 *
 * A number arrives three ways and has to end up the same string every time:
 * typed into the app's sign-in, read out over WhatsApp and typed by staff into
 * an order, and typed again by an admin granting access by hand. It is the key
 * an entitlement is stored and looked up under, so if the two ends disagree
 * about the form, a customer who paid 39 000 ₸ never gets what she paid for
 * and nothing anywhere reports an error.
 *
 * This module exists because there WERE two copies. The one in pgRepository
 * had `/D/` where it meant `/\D/` — stripping literal capital Ds instead of
 * every non-digit — so a paid order was filed under "+7 (707) 345-22-44"
 * while the app asked for "77073452244". Two implementations of an agreement
 * are two chances to disagree; there is one now.
 */

/**
 * Digits only, in the Kazakh national form: 11 digits starting with 7.
 *
 * Accepts what people actually type — `+7 707 345 22 44`, `8 (707) 345-22-44`,
 * `7073452244` — and returns `77073452244` for all three. Anything it cannot
 * place is returned as its digits, unchanged, rather than guessed at.
 */
export function normalizePhone(input: string): string {
  const digits = (input ?? '').replace(/\D/g, '');
  // 8XXXXXXXXXX — the domestic prefix, the same number as 7XXXXXXXXXX.
  if (digits.length === 11 && digits.startsWith('8')) return `7${digits.slice(1)}`;
  // XXXXXXXXXX — written without any country or trunk prefix at all.
  if (digits.length === 10) return `7${digits}`;
  return digits;
}
