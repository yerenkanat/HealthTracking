/**
 * One number, one written form — the key an entitlement lives under.
 *
 * A phone arrives three ways: typed into the app's sign-in, read out over
 * WhatsApp and typed by staff onto an order, and typed again by an admin
 * granting access by hand. All three have to land on the same string, because
 * that string is what a paid course is stored and looked up under. When the
 * two ends disagree, a customer who paid 39 000 ₸ never gets what she paid
 * for and nothing anywhere reports an error — the grant is written, the lookup
 * misses, and both sides think they did their job.
 *
 * There used to be two copies of this function, and one of them said `/D/`
 * where it meant `/\D/`: it stripped literal capital Ds and left the plus, the
 * spaces and the brackets in place. So an order was filed under
 * "+7 (707) 345-22-44" and the app asked for "77073452244".
 */

import { describe, it, expect } from 'vitest';
import { normalizePhone } from '../phone';
import { normalizePhone as viaStaffAuth } from '../http/staffAuth';

describe('however she writes it', () => {
  const same = '77073452244';
  for (const written of [
    '+7 707 345 22 44',
    '+7 (707) 345-22-44',
    '+77073452244',
    '8 707 345 22 44',
    '8(707)345-22-44',
    '87073452244',
    '7073452244', // no prefix at all
    '  +7 707 345 22 44  ',
  ]) {
    it(`${JSON.stringify(written)} is the same customer`, () => {
      expect(normalizePhone(written)).toBe(same);
    });
  }
});

describe('what it refuses to guess', () => {
  it('leaves a number it cannot place as its digits', () => {
    // Not padded, not prefixed, not rejected — returned as what was typed,
    // so a wrong number stays visibly wrong instead of quietly becoming a
    // different, valid one.
    expect(normalizePhone('12345')).toBe('12345');
    expect(normalizePhone('+44 20 7946 0958')).toBe('442079460958');
  });

  it('survives an empty or absent value', () => {
    expect(normalizePhone('')).toBe('');
    expect(normalizePhone(undefined as unknown as string)).toBe('');
  });
});

describe('there is only one of it', () => {
  it('staffAuth and the shop agree, because they are the same function', () => {
    // Two implementations of an agreement are two chances to disagree. This
    // fails the moment somebody reintroduces a private copy.
    expect(viaStaffAuth).toBe(normalizePhone);
  });
});
