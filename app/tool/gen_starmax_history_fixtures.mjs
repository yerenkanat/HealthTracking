/**
 * Golden-fixture generator for the Starmax per-day history parsers.
 *
 * WHY THIS EXISTS
 *
 * The Dart history parsers in app/lib/ble/starmax/starmax_history.dart are a
 * re-implementation of the vendor's shipping JavaScript SDK
 * (docs/sdk-demo/libs/StarmaxSDK/index.js). A test whose expected values I typed
 * in by hand would only prove my Dart agrees with my own reading of their
 * minifier output — which is exactly the way this test could be worthless.
 *
 * So the expectations are not mine. This script feeds device-shaped reply frames
 * through the VENDOR'S OWN `starmaxSDK.notify()` — the same function that runs on
 * shipping handsets — and writes what IT decoded to
 * app/test/fixtures/starmax_history_golden.json. The Dart test replays the same
 * bytes and asserts it reaches the vendor's numbers. Any disagreement between my
 * parser and theirs fails the test.
 *
 * The vendor documentation (docs/UniappSDKDocumentation.md §5.44–5.53, §5.58)
 * contains JSON response shapes but not one raw frame capture, so the vendor's
 * implementation is the only authority on bytes that this repository holds.
 *
 * The frames are delivered the way BLE delivers them: split into 20-byte
 * notifications, first packet carrying the 0xDA header, the rest raw
 * continuations — because the vendor's reassembly is part of the wire format and
 * a parser that only works on whole frames does not work on a watch.
 *
 * Run: node app/tool/gen_starmax_history_fixtures.mjs
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const sdkDir = join(here, '..', '..', 'docs', 'sdk-demo', 'libs', 'StarmaxSDK');
const { starmaxSDK } = await import(pathToFileURL(join(sdkDir, 'index.js')).href);
const { calcCrc } = await import(pathToFileURL(join(sdkDir, 'utils.js')).href);

/** Append the vendor's CRC-16 to a header+payload byte list, little-endian. */
function withCrc(bytes) {
  const crc = parseInt(calcCrc(bytes, bytes.length), 16);
  return [...bytes, crc & 0xff, (crc >> 8) & 0xff];
}

/**
 * One logical history reply frame, exactly as the device lays it out:
 *   0xDA, cmd, thisLen16, status, interval, y-2000, m, d, totalLen16, chunk…, crc16
 * `total` is the whole day's data length; `chunk` is this frame's slice of it.
 */
function historyFrame({ cmd, status = 0, interval, y, m, d, total, chunk }) {
  const payload = [
    status,
    interval,
    y - 2000,
    m,
    d,
    total & 0xff,
    (total >> 8) & 0xff,
    ...chunk,
  ];
  return withCrc([0xda, cmd, payload.length & 0xff, (payload.length >> 8) & 0xff, ...payload]);
}

/** A plain (non-sync) reply frame: 0xDA, cmd, len16, status, payload…, crc16. */
function plainFrame(cmd, status, payload) {
  const body = [status, ...payload];
  return withCrc([0xda, cmd, body.length & 0xff, (body.length >> 8) & 0xff, ...body]);
}

/**
 * Push `frames` through the vendor SDK the way a radio does — 20-byte
 * notifications — and resolve with whatever the SDK decodes.
 *
 * Only the notification that completes the transfer resolves; the vendor leaves
 * the intermediate promises pending for ever, so they are raced rather than
 * awaited.
 */
function decode(frames) {
  const packets = [];
  for (const f of frames) {
    for (let i = 0; i < f.length; i += 20) packets.push(f.slice(i, i + 20));
  }
  const pending = [];
  for (const p of packets) {
    pending.push(
      starmaxSDK
        .notify(Uint8Array.from(p).buffer)
        // The vendor rejects a device error with {code, message}; keep both, so
        // the fixture records what their SDK actually does with a "no data" day.
        .catch((e) => ({ __rejected: { code: e?.code ?? null, message: e?.message ?? String(e) } })),
    );
  }
  return Promise.race([
    Promise.race(pending),
    new Promise((_, rej) => setTimeout(() => rej(new Error('vendor SDK never resolved')), 2000)),
  ]);
}

/** Split a day's data into logical frames of at most `per` payload bytes. */
function split(data, per) {
  const out = [];
  for (let i = 0; i < data.length; i += per) out.push(data.slice(i, i + per));
  return out.length ? out : [[]];
}

// ---------------------------------------------------------------------------
// The day under test. Deliberately not a flat ramp: real watches leave long
// unmeasured stretches, and the vendor encodes "no reading" as 0xFF.
// ---------------------------------------------------------------------------
const Y = 2026;
const M = 8;
const D = 10;

/** A plausible resting/waking heart-rate day, 0xFF where nothing was measured. */
function heartRateDay(n) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const minute = (i * 1440) / n;
    if (minute >= 60 && minute < 150) { out.push(255); continue; } // watch off wrist
    const base = minute < 420 ? 58 : 72;          // asleep vs awake
    out.push(base + ((i * 7) % 19));
  }
  return out;
}

const cases = [];

// --- 5.53 valid history dates (frame 233, not a sync frame) ----------------
cases.push({
  name: 'validHistoryDates',
  doc: '5.53 获取历史数据有效日期',
  replyCmd: 233,
  frames: [
    plainFrame(233, 0, [
      26, 8, 8,
      26, 8, 9,
      26, 8, 10,
    ]),
  ],
});

// --- 5.46 heart rate (227), 5-minute sampling, two logical frames ----------
{
  const data = heartRateDay(288);
  cases.push({
    name: 'heartRate',
    doc: '5.46 同步心率记录',
    replyCmd: 227,
    frames: split(data, 160).map((chunk) =>
      historyFrame({ cmd: 227, interval: 5, y: Y, m: M, d: D, total: data.length, chunk })),
  });
}

// --- 5.48 blood oxygen (229), 30-minute sampling ---------------------------
{
  const data = Array.from({ length: 48 }, (_, i) => (i % 11 === 0 ? 255 : 94 + (i % 5)));
  cases.push({
    name: 'bloodOxygen',
    doc: '5.48 同步血氧数据',
    replyCmd: 229,
    frames: [historyFrame({ cmd: 229, interval: 30, y: Y, m: M, d: D, total: data.length, chunk: data })],
  });
}

// --- 5.47 blood pressure (228), two bytes per sample -----------------------
{
  const data = [];
  for (let i = 0; i < 24; i++) {
    if (i % 7 === 0) { data.push(255, 255); continue; }
    data.push(110 + (i % 13), 68 + (i % 9)); // ss then fz
  }
  cases.push({
    name: 'bloodPressure',
    doc: '5.47 同步血压数据',
    replyCmd: 228,
    frames: [historyFrame({ cmd: 228, interval: 60, y: Y, m: M, d: D, total: data.length, chunk: data })],
  });
}

// --- 5.51 temperature (232), LE16 tenths of a degree per sample ------------
{
  const data = [];
  for (let i = 0; i < 24; i++) {
    if (i % 6 === 0) { data.push(0, 0); continue; }
    const tenths = 362 + (i % 7); // 36.2 – 36.8 °C
    data.push(tenths & 0xff, (tenths >> 8) & 0xff);
  }
  cases.push({
    name: 'temperature',
    doc: '5.51 同步温度数据',
    replyCmd: 232,
    frames: [historyFrame({ cmd: 232, interval: 60, y: Y, m: M, d: D, total: data.length, chunk: data })],
  });
}

// --- 5.49 stress / "pressure" (230) ----------------------------------------
{
  const data = Array.from({ length: 24 }, (_, i) => (i < 6 ? 255 : 28 + (i % 31)));
  cases.push({
    name: 'stress',
    doc: '5.49 同步压力数据',
    replyCmd: 230,
    frames: [historyFrame({ cmd: 230, interval: 60, y: Y, m: M, d: D, total: data.length, chunk: data })],
  });
}

// --- 5.50 MET (231) --------------------------------------------------------
{
  const data = Array.from({ length: 24 }, (_, i) => (i % 9 === 0 ? 255 : 1 + (i % 6)));
  cases.push({
    name: 'met',
    doc: '5.50 同步梅脱数据',
    replyCmd: 231,
    frames: [historyFrame({ cmd: 231, interval: 60, y: Y, m: M, d: D, total: data.length, chunk: data })],
  });
}

// --- 5.58 blood sugar (242) ------------------------------------------------
{
  const data = Array.from({ length: 24 }, (_, i) => (i % 5 === 0 ? 255 : 48 + (i % 23)));
  cases.push({
    name: 'bloodSugar',
    doc: '5.58 同步血糖数据',
    replyCmd: 242,
    frames: [historyFrame({ cmd: 242, interval: 60, y: Y, m: M, d: D, total: data.length, chunk: data })],
  });
}

// --- respiration rate (248) ------------------------------------------------
{
  const data = Array.from({ length: 24 }, (_, i) => (i % 8 === 0 ? 255 : 13 + (i % 6)));
  cases.push({
    name: 'respirationRate',
    doc: '5.60 同步呼吸率数据',
    replyCmd: 248,
    frames: [historyFrame({ cmd: 248, interval: 60, y: Y, m: M, d: D, total: data.length, chunk: data })],
  });
}

// --- sleep stages (244) ----------------------------------------------------
{
  // 288 five-minute slots: awake until 23:00, then a night of light/deep/REM.
  const data = [];
  for (let i = 0; i < 288; i++) {
    const minute = i * 5;
    if (minute < 420) {
      // 00:00–07:00 asleep
      const phase = Math.floor(minute / 45) % 3;
      data.push(i === 0 ? 1 : phase === 0 ? 2 : phase === 1 ? 3 : 5);
    } else if (minute >= 1380) {
      data.push(minute === 1380 ? 1 : 2); // dozed off before midnight
    } else if (minute > 780 && minute < 840) {
      data.push(130); // a nap: 2 (light) + 128
    } else {
      data.push(0);
    }
  }
  cases.push({
    name: 'sleep',
    doc: '5.61 同步睡眠数据',
    replyCmd: 244,
    frames: split(data, 160).map((chunk) =>
      historyFrame({ cmd: 244, interval: 5, y: Y, m: M, d: D, total: data.length, chunk })),
  });
}

// --- 5.45 steps + sleep, six bytes per record (226) ------------------------
{
  const data = [];
  const recs = 24; // 24 records at a 60-minute interval
  for (let i = 0; i < recs; i++) {
    const steps = i < 7 ? 0 : 120 + i * 37;
    const kcal = Math.round(steps * 0.04);
    const dm = steps * 7; // decimetres, per the vendor's unit for step.distance
    const packed = (1 << 12) | (steps & 0x0fff); // dataType 1 = steps
    data.push(
      packed & 0xff, (packed >> 8) & 0xff,
      kcal & 0xff, (kcal >> 8) & 0xff,
      dm & 0xff, (dm >> 8) & 0xff,
    );
  }
  cases.push({
    name: 'steps',
    doc: '5.45 同步计步睡眠',
    replyCmd: 226,
    frames: split(data, 144).map((chunk) =>
      historyFrame({ cmd: 226, interval: 60, y: Y, m: M, d: D, total: data.length, chunk })),
  });
}

// --- a day the watch holds nothing for: the device answers status 4 --------
cases.push({
  name: 'heartRateNoData',
  doc: '5.46 with 数据无效 (status 4)',
  replyCmd: 227,
  expectVendorError: true,
  frames: [historyFrame({ cmd: 227, status: 4, interval: 0, y: Y, m: M, d: 11, total: 0, chunk: [] })],
});

const out = { generatedBy: 'app/tool/gen_starmax_history_fixtures.mjs', cases: [] };
for (const c of cases) {
  let decoded;
  try {
    decoded = await decode(c.frames);
  } catch (e) {
    decoded = { __error: String(e) };
  }
  out.cases.push({
    name: c.name,
    doc: c.doc,
    replyCmd: c.replyCmd,
    // Hex so the fixture is readable and diffable as bytes.
    frames: c.frames.map((f) => f.map((b) => b.toString(16).padStart(2, '0')).join('')),
    vendor: decoded,
  });
}

const dest = join(here, '..', 'test', 'fixtures', 'starmax_history_golden.json');
mkdirSync(dirname(dest), { recursive: true });
writeFileSync(dest, JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${dest} (${out.cases.length} cases)`);
