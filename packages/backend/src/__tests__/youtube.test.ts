/**
 * Reading the video id out of whatever was pasted.
 *
 * Lesson links are pasted by hand, and the validation this replaces only asked
 * whether the string contained "youtube.com" or "youtu.be". That accepts a
 * channel page, a playlist, a search result and a mistyped path — every one of
 * which saves cleanly, publishes to paying customers, and fails in the app
 * where nobody can fix it.
 */

import { describe, it, expect } from 'vitest';
import { youtubeVideoId, youtubeThumbnail } from '../youtube';

const ID = 'dQw4w9WgXcQ';

describe('the shapes a person actually pastes', () => {
  for (const [what, url] of [
    ['the share sheet', `https://youtu.be/${ID}`],
    ['the share sheet with a start time', `https://youtu.be/${ID}?t=42`],
    ['the desktop address bar', `https://www.youtube.com/watch?v=${ID}`],
    ['…without the www', `https://youtube.com/watch?v=${ID}`],
    ['…with tracking junk on the end', `https://www.youtube.com/watch?v=${ID}&feature=share&si=abc`],
    ['…with the parameters reordered', `https://www.youtube.com/watch?feature=share&v=${ID}`],
    ['the mobile site', `https://m.youtube.com/watch?v=${ID}`],
    ['an embed URL', `https://www.youtube.com/embed/${ID}`],
    ['a short', `https://www.youtube.com/shorts/${ID}`],
    ['a livestream', `https://www.youtube.com/live/${ID}`],
    ['http, from an old copy-paste', `http://youtu.be/${ID}`],
    ['with whitespace around it', `  https://youtu.be/${ID}  `],
  ] as const) {
    it(`${what}`, () => {
      expect(youtubeVideoId(url)).toBe(ID);
    });
  }
});

describe('what it refuses, and used to accept', () => {
  for (const [what, url] of [
    ['a channel page', 'https://www.youtube.com/@anabala'],
    ['a playlist', 'https://www.youtube.com/playlist?list=PL123456'],
    ['a search result', 'https://www.youtube.com/results?search_query=roды'],
    ['the bare domain', 'https://youtube.com'],
    ['a share link with the id chopped off', 'https://youtu.be/'],
    ['an id one character short', 'https://youtu.be/dQw4w9WgXc'],
    ['an id with an illegal character', 'https://youtu.be/dQw4w9WgXc!'],
    ['somebody else entirely', 'https://vimeo.com/123456789'],
    ['a lookalike domain', 'https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ'],
    ['not a URL at all', 'первый урок'],
    ['empty', ''],
  ] as const) {
    it(`${what}`, () => {
      expect(youtubeVideoId(url)).toBeNull();
    });
  }

  it('refuses a non-http scheme', () => {
    // javascript: in an href on the panel is the reason this is checked here
    // rather than only in the app.
    expect(youtubeVideoId('javascript:alert(1)//youtu.be/dQw4w9WgXcQ')).toBeNull();
  });
});

describe('the thumbnail used to check a link', () => {
  it('points at the video', () => {
    expect(youtubeThumbnail(ID)).toBe(`https://img.youtube.com/vi/${ID}/mqdefault.jpg`);
  });

  it('is the size that 404s on an unknown video', () => {
    // hqdefault answers with a grey placeholder for an id that does not exist,
    // which looks like a real thumbnail that happens to be dull. mqdefault
    // answers 404, which the panel can act on.
    expect(youtubeThumbnail(ID)).toContain('mqdefault');
    expect(youtubeThumbnail(ID)).not.toContain('hqdefault');
  });
});
