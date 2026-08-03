// Unpack the Ana-Bala landing artifact into static files the backend serves.
//
// The landing is authored elsewhere and exported as a single self-extracting
// HTML file (docs/Ana-Bala Landing.html): a small loader plus base64 islands
// holding the page template, every font/image, and the React UMD bundles. That
// file WORKS in a browser, but shipping it as the site root would mean a 2.7 MB
// base64 payload re-downloaded on every visit, nothing cacheable, and a blank
// page for any crawler that does not run JavaScript.
//
// So we do the loader's job here, once, at build time: decode the islands to
// real files, rewrite the uuid references to real URLs, and emit a plain
// index.html. The result is ordinary static hosting — cacheable assets, a head
// crawlers can read, no unpacking on the client.
//
// Re-run after every re-export of the artifact:
//     node packages/backend/tools/build-landing.mjs
//
// Output (git-tracked, served by src/index.ts):
//     packages/backend/landing/index.html
//     packages/backend/landing/a/<uuid>.<ext>   fonts, images, react, runtime
//
// landing/wire.js is NOT generated — it is hand-written (ours, not the
// artifact's) and deliberately sits OUTSIDE landing/a/, which this script
// wipes on every run. See its header.
import { readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '../../../docs/Ana-Bala Landing.html');
const OUT = join(HERE, '../landing');
const ASSETS = join(OUT, 'a');

// The public URL prefix the rewritten template points at. Must match the route
// registered in src/index.ts.
const BASE = '/landing/a';

// mime → extension. Only what the bundle actually carries; an unknown mime is
// a signal the artifact gained a new asset kind, so fail loudly rather than
// emit a file the server will serve as the wrong type.
const EXT = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/webp': 'webp',
  'image/svg+xml': 'svg',
  'image/gif': 'gif',
  'font/woff2': 'woff2',
  'font/woff': 'woff',
  'text/javascript': 'js',
  'application/javascript': 'js',
  'text/css': 'css',
};

/** Pull one `<script type="__bundler/NAME">…</script>` island out of the export. */
function island(html, name) {
  const open = `<script type="__bundler/${name}">`;
  const i = html.indexOf(open);
  if (i < 0) return null;
  const start = i + open.length;
  const end = html.indexOf('</script>', start);
  if (end < 0) throw new Error(`unterminated __bundler/${name} island`);
  return html.slice(start, end).trim();
}

const html = readFileSync(SRC, 'utf8');
const manifest = JSON.parse(island(html, 'manifest') ?? '{}');
const extResources = JSON.parse(island(html, 'ext_resources') ?? '[]');
const pageOrder = JSON.parse(island(html, 'page_order') ?? '[]');
let template = JSON.parse(island(html, 'template') ?? 'null');

if (!template) throw new Error('no __bundler/template island — is this a bundler export?');
// Nested page bundles ride as about:blank#uuid iframe markers the client loader
// resolves at runtime. Nothing here mints blobs, so a page bundle would render
// as an empty frame; the current landing has none and we refuse to ship a
// silently broken one.
if (pageOrder.length) throw new Error(`bundle has ${pageOrder.length} nested page(s); static unpack does not support them`);

// Start clean so assets dropped by a re-export do not linger and get served.
rmSync(ASSETS, { recursive: true, force: true });
mkdirSync(ASSETS, { recursive: true });

// ---- 1. Decode every asset to a real file -----------------------------------
/** @type {Record<string,string>} uuid → public URL */
const urls = {};
let bytesOut = 0;
for (const [uuid, entry] of Object.entries(manifest)) {
  const ext = EXT[entry.mime];
  if (!ext) throw new Error(`unknown mime "${entry.mime}" for ${uuid} — add it to EXT`);
  let bytes = Buffer.from(entry.data, 'base64');
  if (entry.compressed) bytes = gunzipSync(bytes); // the loader's DecompressionStream step
  writeFileSync(join(ASSETS, `${uuid}.${ext}`), bytes);
  urls[uuid] = `${BASE}/${uuid}.${ext}`;
  bytesOut += bytes.length;
}

// ---- 2. Rewrite uuid references to real URLs --------------------------------
// The loader does `template.split(uuid).join(blobUrl)`; the only difference here
// is that the replacement survives a page load.
for (const [uuid, url] of Object.entries(urls)) template = template.split(uuid).join(url);

// SRI hashes name the CDN copies of React, not our local copies — same reason
// the loader strips them.
template = template.replace(/\s+integrity="[^"]*"/gi, '').replace(/\s+crossorigin="[^"]*"/gi, '');

// ---- 3. Point the runtime's CDN lookups at the local copies ------------------
// dc-runtime loads React/ReactDOM through `window.__resources[cdnUrl]`, falling
// back to unpkg.com when a URL is missing. The fallback must never fire: the
// page would then depend on a third-party CDN at runtime.
const resourceMap = {};
for (const r of extResources) {
  if (!urls[r.uuid]) throw new Error(`ext_resource ${r.id} has no asset for uuid ${r.uuid}`);
  resourceMap[r.id] = urls[r.uuid];
}
// `</` inside a JSON string would close this very script element.
const resourceScript = `<script>window.__resources = ${JSON.stringify(resourceMap).replace(/<\//g, '<\\/')};</script>`;

const headOpen = /<head[^>]*>/i.exec(template);
if (!headOpen) throw new Error('template has no <head>');
let headEnd = headOpen.index + headOpen[0].length;
template = template.slice(0, headEnd) + '\n' + resourceScript + template.slice(headEnd);
headEnd += 1 + resourceScript.length;

// ---- 3b. Hoist the page title out of <helmet> and into <head> ---------------
// The artifact declares its <title> inside a <helmet> block in the body, which
// the runtime copies into <head> after React boots. That is too late for a
// crawler and too late for a social scraper, so the server needs a title in the
// first byte — but if BOTH put one there, <head> ends up with two <title>
// elements and which one wins is anyone's guess. Move it rather than copy it:
// one title, in the right place, still authored in the artifact.
const helmet = /<helmet[^>]*>[\s\S]*?<\/helmet>/i.exec(template);
if (!helmet) throw new Error('template has no <helmet> block — where did the title go?');
const titleTag = /<title>[\s\S]*?<\/title>/i.exec(helmet[0]);
if (!titleTag) throw new Error('no <title> inside <helmet>');
template =
  template.slice(0, headEnd) + titleTag[0] +
  template.slice(headEnd).replace(helmet[0], helmet[0].replace(titleTag[0], ''));

// ---- 3c. Make it fit a phone ------------------------------------------------
//
// The artifact is authored at desktop width and every rule in it is an INLINE
// style, so there is no class to override and no breakpoint anywhere: on a
// 390px screen the page scrolled sideways, headings ran off the edge and the
// two-column sections stayed two columns.
//
// Hence attribute selectors — `[style*="…"]` matches the inline declarations
// the export actually wrote. Ugly, but it is the only hook a generated page
// offers, and it survives a re-export because it matches on values (grid,
// font-size:66px) rather than on markup that could be renamed.
//
// Injected here rather than hand-edited into the export for the same reason.
//
// One trap, learned the hard way: React RE-SERIALISES every inline style when
// it renders, so `font-size:66px` in the export becomes `font-size: 66px` in
// the DOM (and `.95fr` becomes `0.95fr`, `0` becomes `0px`). Selectors written
// against the compact form match nothing at runtime — the first version of this
// silently fixed only the rules whose selector named a property and no value.
// Every value selector below therefore lists both spellings.
const fs_ = (px, to) =>
  `  [style*="font-size:${px}px"], [style*="font-size: ${px}px"] { font-size: ${to} !important; }`;

const RESPONSIVE_CSS = `
/* Ana-Bala landing — phone layer, added by tools/build-landing.mjs */
@media (max-width: 900px) {
  html, body { overflow-x: hidden !important; max-width: 100vw; }

  /* Every multi-column section becomes one column. */
  [style*="grid-template-columns"] { grid-template-columns: 1fr !important; }

  /* Desktop section padding is most of a phone's width. */
  [style*="padding:96px"], [style*="padding: 96px"] { padding: 48px 16px !important; }
  [style*="padding:72px"], [style*="padding: 72px"] { padding: 36px 16px !important; }
  [style*="padding:52px"], [style*="padding: 52px"] { padding: 24px 18px !important; }
  section { padding-left: 16px !important; padding-right: 16px !important; }

  /* Type. Russian compounds are long, so these are vw-based with a floor. */
${fs_(66, 'clamp(30px, 9vw, 46px)')}
${fs_(62, 'clamp(30px, 9vw, 46px)')}
${fs_(52, 'clamp(25px, 7.5vw, 36px)')}
${fs_(50, 'clamp(25px, 7.5vw, 36px)')}
${fs_(48, 'clamp(25px, 7.5vw, 36px)')}
${fs_(46, 'clamp(24px, 7vw, 34px)')}
${fs_(44, 'clamp(24px, 7vw, 34px)')}
${fs_(42, 'clamp(23px, 6.5vw, 32px)')}
${fs_(40, 'clamp(22px, 6vw, 30px)')}
${fs_(38, 'clamp(21px, 5.5vw, 28px)')}
${fs_(36, '22px')}
${fs_(34, '21px')}
${fs_(30, '20px')}
${fs_(28, '19px')}
${fs_(26, '18px')}
${fs_(24, '18px')}
${fs_(20, '16px')}
${fs_(19, '16px')}

  /* A single unbreakable word must not widen the page. */
  h1, h2, h3, p, div, span, a { overflow-wrap: break-word; }

  /* Nothing may be wider than the screen — including the decorative blobs
     positioned absolutely behind the hero. */
  img, video, svg, iframe { max-width: 100% !important; height: auto !important; }
  [style*="position:absolute"], [style*="position: absolute"] { max-width: 100vw !important; }

  /* Rows of chips/links wrap instead of pushing the page wide. */
  [style*="display:flex"]:not([style*="column"]),
  [style*="display: flex"]:not([style*="column"]) { flex-wrap: wrap; }
}

/* The header's in-page anchors do not fit beside the logo and the WhatsApp
   button. The hero repeats every one of them as a CTA, so hiding the strip
   costs no navigation. */
@media (max-width: 720px) {
  header a[href^="#"], nav a[href^="#"] { display: none !important; }
}
`;
template = template.slice(0, headEnd) + `<style>${RESPONSIVE_CSS}</style>` + template.slice(headEnd);
headEnd += RESPONSIVE_CSS.length + 15;

// ---- 4. Wire the callback form (ours, not the artifact's) -------------------
// Appended rather than patched into the artifact's own script so it survives a
// re-export of the landing unchanged.
template = template.replace(/<\/body>/i, '<script src="/landing/wire.js" defer></script>\n</body>');

writeFileSync(join(OUT, 'index.html'), template, 'utf8');

const assetCount = readdirSync(ASSETS).length;
console.log(`landing/index.html  ${(template.length / 1024).toFixed(0)} KB`);
console.log(`landing/a/          ${assetCount} files, ${(bytesOut / 1024 / 1024).toFixed(2)} MB`);
console.log(`__resources         ${Object.keys(resourceMap).length} external URL(s) mapped locally`);
