#!/usr/bin/env node
/**
 * How much of the two specs is actually built?
 *
 *   node tools/spec-coverage.mjs
 *
 * WHY THIS IS A SCRIPT AND NOT A DOCUMENT
 *
 * A hand-written progress list is out of date the day after it is written, and
 * the failure is silent: it keeps reading like an answer. This derives the
 * number from the specs and the source every time it runs, so it is either
 * right or obviously broken.
 *
 * WHAT IT CANNOT TELL YOU, and this matters more than the number:
 * a frame counts as "built" when something in the code claims it. That is
 * evidence of intent, not of a working screen. This repo's dominant defect is
 * finished code with no caller — a view that renders perfectly and nothing
 * navigates to. So read the count as "how much has been attempted", and trust
 * the render tests and deploy/verify-live.sh for whether it works.
 */

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

/** Every file under a directory, recursively, matching an extension. */
function walk(dir, ext, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, ext, out);
    else if (e.name.endsWith(ext)) out.push(p);
  }
  return out;
}

// ---- The admin panel: 76 frames -------------------------------------------
//
// A frame is built when the panel has a view for it. The mapping is explicit
// rather than guessed from numbering: several spec frames share one view on
// purpose (05/05a/05b are one Финансы screen), and pretending otherwise would
// either overcount or demand screens the design does not want.
const ADMIN_VIEW_FOR = {
  '00': 'owner', '01': 'overview', '19': 'emergencies', '20': 'analytics',
  '02': 'shop', '03': 'shop', '04': 'shop',
  '05': 'finance', '05a': 'finance', '05b': 'finance',
  // 06 «Маркетинг» — рассылки. Shipped in f911c55 with its own view, and this
  // map was never updated, so the report kept listing a built screen as
  // missing. A stale "not built" is the same defect as a stale "built": a
  // number nobody can act on.
  '06': 'marketing',
  // 07a «Поставки» и 07g «Поставщики» живут в той же вкладке Склад: карточки
  // #stockSupplyCard и #stockSuppliersCard, со своими пунктами меню. Отдельная
  // вкладка под заказы поставщикам разорвала бы «на сколько хватит» и «что уже
  // едет» — два ответа на один вопрос закупщика.
  '07': 'stock', '07a': 'stock', '07c': 'stock', '07g': 'stock',
  '08': 'catalog', '08a': 'catalog', '08b': 'catalog',
  '09': 'users', '09a': 'users', '10': 'kids', '11': 'devices', '12': 'support',
  '13': 'antenatal', '14': 'pregweeks', '14a': 'pregweeks', '14b': 'pregweeks',
  '14c': 'childdev', '15': 'vaccines', '16': 'content',
  // 16b «Экстренная помощь» — its own view, not «Уроки и товары»: the
  // scenarios behind app screen 37 are a separate table with a separate
  // editor, and mapping it onto `content` would report it as built because a
  // neighbouring screen exists.
  '16b': 'emergency-help',
  '17': 'audio',
  // 17c «Детектор плача» — its own view, not «Аудио»: the two share nothing but
  // a spec number. Audio is clips somebody uploads for a calendar day; this is
  // the classifier's accuracy and the confidence threshold below which the app
  // names no reason. Mapping it onto `audio` would report it as built because a
  // neighbouring screen exists.
  '17c': 'cry',
  '18': 'course', '21': 'review', '22': 'security', '23': 'staff',
  '23a': 'roles', '24': 'integrations', '24b': 'integrations',
  // 25 «Уведомления» — its own view, not a card on «Маркетинг»: frame 06
  // answers «кому мы решили написать» and this one answers «дошло ли, а если
  // нет, то почему». Mapping it onto `marketing` would report it as built
  // because a neighbouring screen exists — the failure this map already
  // carries three warnings about.
  '25': 'notifications',
};

function adminCoverage() {
  const spec = read(join(root, 'docs/CLAUDE-admin-design.md'));
  const panel = read(join(root, 'packages/admin/index.html'));
  const views = new Set([...panel.matchAll(/data-view="([a-z0-9_-]+)"/g)].map((m) => m[1]));

  // The spec lists frames as **NN · Title** inside PART 4.
  const part4 = spec.slice(spec.indexOf('ЧАСТЬ 4'));
  const frames = [...part4.matchAll(/\*\*(\d{2}[a-z]?)\s*·\s*([^*]+?)\*\*/g)]
    .map((m) => ({ id: m[1], title: m[2].trim() }));

  const seen = new Set();
  const unique = frames.filter((f) => (seen.has(f.id) ? false : seen.add(f.id)));

  const built = [], missing = [];
  for (const f of unique) {
    const view = ADMIN_VIEW_FOR[f.id];
    (view && views.has(view) ? built : missing).push(f);
  }
  return { total: unique.length, built, missing, views: [...views].sort() };
}

// ---- The app: 59 screens ---------------------------------------------------
//
// A screen is built when a Dart file's header names it — the convention this
// codebase already follows ("/// Screen 44 — «Аудио дня · плеер»"). That is a
// claim by the author, which is exactly what this report measures.
/**
 * Spec screen → the file that implements it.
 *
 * An explicit map, not a scan for «Screen NN» comments. The first version of
 * this did scan, and reported 34% — while screens 01, 02 and 03 were not only
 * built but driven end to end on a device by
 * integration_test/onboarding_device_test.dart. They simply carry no numbered
 * comment. A progress figure that undercounts by a third is the same defect as
 * one that overcounts: a number nobody can act on.
 *
 * A file listed here is a CLAIM that the screen was attempted, checked against
 * the file existing. Whether it is reachable is a different question — see the
 * note printed at the end.
 */
const APP_FILE_FOR = {
  '01': 'ui/onboarding/onboarding_flow.dart', '02': 'ui/auth/sign_in_screen.dart',
  '03': 'ui/auth/sign_in_screen.dart', '35': 'ui/onboarding/onboarding_flow.dart',
  '36': 'ui/onboarding/onboarding_flow.dart',
  '53': 'ui/dashboard/health_dashboard_screen.dart', '55': 'ui/dashboard/health_dashboard_screen.dart',
  '04': 'ui/dashboard/health_dashboard_screen.dart', '05': 'ui/dashboard/health_dashboard_screen.dart',
  '06': 'ui/calibration/bp_calibration_sheet.dart', '07': 'ui/chat/assistant_chat_screen.dart',
  '08': 'ui/calendar/week_detail_screen.dart', '09': 'ui/calendar/womens_health_screen.dart',
  '10': 'ui/calendar/contraction_timer_screen.dart', '11': 'ui/calendar/womens_health_screen.dart',
  '12': 'ui/tracking/child_map_screen.dart', '13': 'ui/tracking/zones_screen.dart',
  '14': 'ui/tracking/vaccination_screen.dart', '15a': 'ui/tracking/cry_insight_screen.dart',
  '15b': 'ui/tracking/cry_insight_screen.dart', '15c': 'ui/tracking/cry_insight_screen.dart',
  '15d': 'ui/tracking/cry_insight_screen.dart', '15e': 'ui/tracking/cry_insight_screen.dart',
  '16': 'ui/profile/profile_screen.dart', '17': 'ui/content/lesson_player_screen.dart',
  '18': 'ui/settings/settings_screen.dart', '19': 'ui/common/skeleton.dart',
  '20': 'ui/tracking/child_map_screen.dart', '21': 'ui/tracking/child_safety_screen.dart',
  '22': 'ui/tracking/night_feed_screen.dart', '23': 'ui/theme.dart',
  '24': 'ui/tracking/child_detail_screen.dart', '25': 'ui/tracking/newborn_log_screen.dart',
  // 26 «Медкарта» — the child's emergency medical card: blood type, allergies,
  // chronic conditions, who to call. It was reported missing long after it was
  // built and wired (child_detail_screen.dart pushes it), because this map was
  // never updated. A stale "not built" is the same defect as a stale "built":
  // a number nobody can act on.
  '26': 'ui/tracking/child_emergency_screen.dart',
  // 27 «Гиды» — the library over the WHOLE published catalogue: search, the
  // 2x2 of topics, the red-flag card, and her own stage. Deliberately not
  // mapped to timeline_content_screen, which is one stage's shelf; that
  // mapping would have reported this as built because a nearby screen existed,
  // while 363 of the 364 published items stayed unreachable.
  '27': 'ui/content/guides_screen.dart',
  // 28 «Сопряжение Bluetooth» is the pairBand step inside the onboarding flow
  // rather than a screen of its own — which is a design decision, not a gap.
  '28': 'ui/onboarding/onboarding_flow.dart', '29': 'ui/tracking/alerts_screen.dart',
  '30': 'ui/calendar/postpartum_screen.dart', '31': 'ui/calendar/medications_screen.dart',
  '32': 'ui/appointments/appointments_screen.dart', '33': 'ui/calendar/day_log_sheet.dart',
  '34': 'ui/content/mama_course_screen.dart',
  // 37 «Экстренная помощь» — the 103 card, the scenarios, the dispatcher's
  // address and «Позвонить педиатру». Deliberately NOT
  // emergency_rescue_screen.dart, which is the TRIAGE screen that appears by
  // itself: that mapping reported this frame as built while the only thing
  // «Гиды» could open was one paragraph and one button.
  '37': 'ui/emergency/emergency_help_screen.dart',
  '38': 'data/notification_service.dart', '39': 'ui/tracking/notification_centre_screen.dart',
  '40': 'ui/profile/family_access_screen.dart', '41': 'ui/shop/shop_screen.dart',
  '42': 'ui/profile/my_order_screen.dart', '43': 'ui/settings/help_support_screen.dart',
  '44': 'ui/content/audio_player_screen.dart', '45': 'ui/content/mama_course_screen.dart',
  '46': 'ui/tracking/child_detail_screen.dart', '47': 'ui/tracking/day_history_screen.dart',
  '48': 'ui/tracking/day_event_screen.dart', '49': 'ui/tracking/child_development_screen.dart',
  '50': 'ui/calendar/kick_session_screen.dart', '51': 'ui/calendar/pregnancy_weight_screen.dart',
  '52': 'ui/calendar/hospital_bag_screen.dart', '54': 'ui/calendar/womens_health_screen.dart',
};

function appCoverage() {
  const spec = read(join(root, 'docs/CLAUDE-app-design.md'));
  const frames = [...spec.matchAll(/^\*\*(\d{2}[a-z]?)\s*·\s*([^*]+?)\*\*/gm)]
    .map((m) => ({ id: m[1], title: m[2].trim() }));
  const seen = new Set();
  const unique = frames.filter((f) => (seen.has(f.id) ? false : seen.add(f.id)));

  const built = [], missing = [], stale = [];
  for (const f of unique) {
    const rel = APP_FILE_FOR[f.id];
    if (!rel) { missing.push(f); continue; }
    // A mapping pointing at a file that no longer exists is worse than no
    // mapping: it reports a screen as built because somebody once typed a path.
    if (existsSync(join(root, 'app/lib', rel))) built.push(f);
    else { missing.push(f); stale.push(`${f.id} → app/lib/${rel}`); }
  }
  return { total: unique.length, built, missing, stale };
}

const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);
const bar = (n) => '█'.repeat(Math.round(n / 5)).padEnd(20, '·');

const admin = adminCoverage();
const app = appCoverage();

console.log('\n=== Ana-Bala — how much of the spec is attempted ===\n');
for (const [name, c] of [['Admin panel', admin], ['App', app]]) {
  const p = pct(c.built.length, c.total);
  console.log(`${name.padEnd(12)} ${bar(p)} ${String(p).padStart(3)}%  ${c.built.length}/${c.total}`);
}

console.log('\n--- admin frames with no view ---');
for (const f of admin.missing) console.log(`  ${f.id.padEnd(4)} ${f.title}`);

console.log('\n--- app screens nothing claims ---');
for (const f of app.missing) console.log(`  ${f.id.padEnd(4)} ${f.title}`);

console.log(`\nPanel views present: ${admin.views.join(', ')}`);
console.log(
  '\nNOTE: "attempted", not "working". A frame counts when the code claims it,\n' +
  'and this repo\'s commonest defect is a finished screen nothing navigates to.\n' +
  'For whether it actually works: the render tests, and deploy/verify-live.sh.\n',
);
