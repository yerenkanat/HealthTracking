/**
 * Helpers shared by every server-rendered public page (the landing page and the
 * storefront): HTML escaping for values interpolated into meta tags, and the
 * origin a request arrived on.
 */

/** Escape a value for an HTML attribute or text node. */
export const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');

/**
 * The public origin of this request — `https://ana-bala.kz` in production,
 * `http://127.0.0.1:8080` in dev. og:url and og:image must be absolute, and
 * deriving them from the request keeps the tags correct on both without a
 * hardcoded domain. Behind Caddy the real host/scheme arrive in x-forwarded-*.
 */
export const requestBase = (req: {
  headers: Record<string, string | string[] | undefined>;
  protocol?: string;
}): string => {
  const host = (req.headers['x-forwarded-host'] as string) || (req.headers.host as string) || 'ana-bala.kz';
  const proto = (req.headers['x-forwarded-proto'] as string) || req.protocol || 'https';
  return `${proto}://${host}`;
};
