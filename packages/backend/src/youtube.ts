/**
 * The video id inside a YouTube link, or null.
 *
 * Lesson links are pasted by hand from a browser or a phone's share sheet, and
 * those produce half a dozen shapes — youtu.be/ID, /watch?v=ID, /embed/ID,
 * /shorts/ID, /live/ID, any of them with tracking parameters bolted on. The
 * validation this replaces only asked whether the string CONTAINED
 * "youtube.com" or "youtu.be", which accepts a channel page, a playlist, a
 * search result and a mistyped path — all of which save cleanly, publish to
 * paying customers, and fail in the app where nobody can fix them.
 *
 * Extracting the id is also what makes a link checkable before it ships: with
 * an id the panel can show the video's own thumbnail, and a wrong paste
 * becomes visible at the moment it is made.
 */

/** YouTube ids are 11 characters of URL-safe base64. */
const ID = /^[A-Za-z0-9_-]{11}$/;

/** Paths that carry the id as their first segment. */
const PATH_PREFIXES = ['embed', 'shorts', 'live', 'v'];

export function youtubeVideoId(input: string): string | null {
  const raw = (input ?? '').trim();
  if (!raw) return null;

  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;

  const host = url.hostname.toLowerCase().replace(/^www\./, '');
  const segments = url.pathname.split('/').filter(Boolean);

  // youtu.be/ID — the share-sheet form, and the one most often pasted.
  if (host === 'youtu.be') {
    return ID.test(segments[0] ?? '') ? segments[0] : null;
  }

  if (host !== 'youtube.com' && host !== 'm.youtube.com' && host !== 'music.youtube.com') {
    return null;
  }

  // /watch?v=ID
  const v = url.searchParams.get('v');
  if (v && ID.test(v)) return v;

  // /embed/ID, /shorts/ID, /live/ID, /v/ID
  if (segments.length >= 2 && PATH_PREFIXES.includes(segments[0].toLowerCase())) {
    return ID.test(segments[1]) ? segments[1] : null;
  }

  return null;
}

/**
 * The still image YouTube serves for a video.
 *
 * mqdefault rather than hqdefault: YouTube answers 404 for an unknown video on
 * mqdefault, and a grey placeholder image on hqdefault. A 404 is a signal the
 * panel can act on; a grey rectangle looks like a real thumbnail that happens
 * to be dull.
 */
export function youtubeThumbnail(videoId: string): string {
  return `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`;
}
