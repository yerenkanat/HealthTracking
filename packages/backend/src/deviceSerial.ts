/**
 * Normalising a device serial.
 *
 * The id the app sends is a BLE MAC, and a MAC is written six different ways
 * depending on who printed the label: `AA:BB:CC:DD:EE:FF`, `aa-bb-cc-dd-ee-ff`,
 * `AABBCCDDEEFF`, with spaces, in either case. The warehouse types one of them
 * and the phone reports another.
 *
 * A registry that misses a unit over punctuation is worse than no registry: it
 * refuses a customer who bought from us, which is the exact outcome this whole
 * feature exists to avoid. So both sides go through here, always.
 */
export function normalizeSerial(raw: string): string {
  return raw.replace(/[^0-9A-Za-z]/g, '').toUpperCase();
}

/** Does this look like a BLE MAC — twelve hex digits once normalised? */
export function looksLikeMac(raw: string): boolean {
  return /^[0-9A-F]{12}$/.test(normalizeSerial(raw));
}
