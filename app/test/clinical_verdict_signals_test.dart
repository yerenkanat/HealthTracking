/// A clinical verdict can be DRAWN instead of written, and nothing hashed it.
///
/// `reviewed_medical_copy_test.dart` fingerprints 508 medical strings so none
/// can drift without a verdict. Every guard in it hashes STRINGS. On
/// 2026-08-19 the clinical gate removed «Цель достигнута» from the kick
/// counter and found the same verdict standing in four places, two of which
/// carried no words at all:
///
///   · the disc and the progress ring turned `Palette.good` — mint, this app's
///     «healthy» colour — the moment the count reached ten;
///   · every history row with ten or more ended in a green `Icons.check_rounded`.
///
/// Both had survived two copy reviews and would have survived every future
/// one, because a fingerprint over `L10n.t` cannot see a colour. The same
/// shape had appeared hours earlier: an amber tile graded blood pressure
/// against an uncited 135/85 while a token test already forbade PRINTING the
/// number — the colour published the band anyway.
///
/// So this file does for drawn claims what the manifest does for written ones:
/// every verdict-bearing colour and icon on a clinical screen must be
/// REGISTERED with what it asserts and on what authority. An unregistered one
/// fails the build. It does not replace anything in
/// `reviewed_medical_copy_test.dart`; it sits beside it.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT COUNTS AS A VERDICT SIGNAL — see [_verdictColour] and [_verdictIcon].
///
/// Mint, amber, the danger coral, and the tick/warning icon family. NOT
/// `Palette.textDim`: `c316c29` established that dim means STALE — "we have
/// not heard from the device", a claim about the app, not about her body — and
/// pulling it in here would have made this guard fire on every greyed-out row
/// in the app.
///
/// Two things about the colour list are deliberate and cost something:
///
///   · It matches the NAME THE AUTHOR WROTE, not the resolved value. It has to.
///     `Palette.danger`, `Palette.violet` and `Palette.roseDeep` are all
///     `Ds.coralText` — one pixel value, and it is also the brand accent on
///     every ordinary link in the product. A guard keyed on the value would
///     fire on half the app; a guard keyed on the name catches the author who
///     meant "danger" and misses the one who spells danger `Palette.roseDeep`.
///     That miss is real and is written down rather than papered over.
///   · `Palette.teal` and `Ds.mint` ARE included even though neither name says
///     "good". They are the identical pixel to `Palette.good`. Leaving them out
///     would mean the ring on the kick screen could come back mint tomorrow
///     under another name and this file would say nothing.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHERE IT APPLIES — see [_clinicalSurfaces].
///
/// Scoping is the whole problem. `Palette.good | danger | amber` appears 138
/// times in `lib/ui`, most of them a button, an order status, a battery, a
/// geofence, a form error. A guard that fires on those stops being believed,
/// and then somebody loosens it — which this repo learned on 2026-08-18 when a
/// deny-list on «роддом» flagged «Сумка в роддом», a packing list.
///
/// THE LINE DRAWN HERE: a file is a clinical surface when the thing its colour
/// can grade is A BODY — a vital sign, a symptom, a physiological count, a
/// growth or sleep or hydration measure, a mood score, or a triage verdict
/// derived from one — or when it renders authored clinical guidance about a
/// body. It is NOT a clinical surface when its colours grade the app, the
/// device, the network, an order, an appointment, a login or a location, even
/// though those use the same three colours. Medication adherence and the
/// hospital-bag checklist sit just outside that line and say so in
/// [_offSurfaces]; they are the closest calls in the file.
///
/// Scope cannot be a list somebody remembers to update, so it is a list with a
/// TRIPWIRE. `isMedicalKey` — the predicate `reviewed_medical_copy_test`
/// already uses to decide what is clinical copy — is applied to the literal
/// l10n keys of every file in `lib/ui`. Any file that renders reviewed medical
/// copy AND draws a verdict signal must appear in [_clinicalSurfaces] or in
/// [_offSurfaces] with a reason. A new clinical screen therefore cannot be
/// built without landing in one of the two lists. Screens that get their
/// clinical text dynamically (the ADV_ cards, the CS_ tips, the triage alerts)
/// have no literal keys to match, so they are named in [_clinicalSurfaces] by
/// hand — the same prefix/explicit-key split the string manifest uses.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT A REGISTRATION MUST CONTAIN — see [_Sig].
///
/// A file:line is not enough; the point is that somebody SAID what the colour
/// asserts, so a reviewer can disagree with it. Every entry carries:
///
///   · `claim`  — what a reader is entitled to conclude from seeing it. This
///                is where a bad one becomes obvious: writing down "her
///                movement count is fine" for the kick ring is precisely the
///                sentence the gate refused, and no one could have typed it
///                without noticing.
///   · `basis`  — on whose authority, or why it is not a clinical claim at all.
///                `_noClaim` is a legitimate answer and most entries use it;
///                it means "this colour does not vary with a reading", and it
///                is an assertion a reviewer can check against the source line.
///
/// The count is part of the registration. Two mints in a class where one is
/// registered fails, so a second verdict cannot ride in on the first one's
/// reason.
///
/// WHEN THIS FAILS, THE FIX IS NOT TO ADD AN ENTRY AND MOVE ON. It is to ask
/// what the colour tells a woman who reads it, and to take that sentence to
/// the clinical gate if it grades her. Adding `claim: 'n/a'` to make a build
/// green is the exact act this file exists to prevent.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'reviewed_medical_copy_test.dart' show isMedicalKey;

// ---------------------------------------------------------------------------
// The signals
// ---------------------------------------------------------------------------

/// Colour tokens that publish a grade. Matched by NAME, in source.
///
/// `Palette.watch` and `Ds.amber` are the same amber; `Palette.good`,
/// `Palette.teal`, `Ds.mint` the same mint; all of them are listed because all
/// of them paint the same pixels on a screen a woman reads.
final _verdictColour = RegExp(
  r'\b(?:Palette\.(?:good|goodText|teal|amber|watch|danger)'
  r'|Ds\.(?:mint|mintDeep|mintCta|mintText|pastelMint|amber|amberText|sos))\b',
);

/// Icons that carry a verdict on their own: a tick, a warning, an alarm.
///
/// The tick half matters as much as the colour half — the instance nobody
/// found for a year was `Icons.check_rounded`, and its colour was only the
/// second thing wrong with it.
final _verdictIcon = RegExp(
  r'\bIcons\.(?:check|done|verified|task_alt|thumb_up|warning|error'
  r'|report|priority_high|dangerous|sos|crisis_alert)\w*\b',
);

// ---------------------------------------------------------------------------
// The scope
// ---------------------------------------------------------------------------

/// Files whose colours can grade a body. Every verdict signal inside one of
/// these must be registered below.
const _clinicalSurfaces = <String, String>{
  // -- The wearable/vitals surface -----------------------------------------
  'lib/ui/dashboard/health_dashboard_screen.dart':
      'the metric tiles, the peace ring and the repeat-reading prompt: every '
          'reading the wearable produces is graded here',
  'lib/ui/dashboard/metric_detail_screen.dart':
      'one vital over time, with an out-of-range band painted behind it',
  'lib/ui/dashboard/health_summary.dart': 'the shareable vitals summary',
  'lib/ui/dashboard/device_temp_note.dart':
      'the qualifier on a skin-temperature estimate',
  'lib/ui/dashboard/sleep_card.dart': 'grades a night of sleep',
  'lib/ui/dashboard/sleep_detail_screen.dart':
      'grades sleep duration and consistency',
  'lib/ui/dashboard/log_sleep_sheet.dart':
      'sleep she types in herself, which the same grader then reads',
  'lib/ui/dashboard/water_card.dart': 'grades hydration against a daily target',
  'lib/ui/dashboard/water_history_screen.dart': 'the same target, per day',
  'lib/ui/calibration/bp_calibration_sheet.dart':
      'takes a cuff reading and tells her whether the device can be trusted '
          'against it',
  // -- The advisory pipeline ------------------------------------------------
  'lib/ui/advisor/advisor_screen.dart':
      'renders the ADV_ cards — the reviewed advisory surface — and their tone',
  'lib/ui/advisor/advisory_body.dart': 'the red-flag block inside an advisory',
  'lib/ui/advisor/advisory_detail_screen.dart': 'one advisory, full text',
  // -- Emergency ------------------------------------------------------------
  'lib/ui/emergency/emergency_help_screen.dart':
      '«Экстренная помощь»: the severity of each scenario is a triage verdict',
  'lib/ui/emergency/emergency_rescue_screen.dart': 'the 103 confirmation gate',
  'lib/ui/tracking/sos_alert_screen.dart': 'a live SOS from a child device',
  'lib/ui/widgets/call_ambulance.dart': 'the ambulance button and its hint',
  // -- Pregnancy ------------------------------------------------------------
  'lib/ui/calendar/kick_session_screen.dart':
      'the fetal-movement counter — the screen this guard was written for',
  'lib/ui/calendar/womens_health_screen.dart':
      'the kick history, the cycle calendar and the symptom cards',
  'lib/ui/calendar/contraction_timer_screen.dart':
      'the 5-1-1 rule: when to leave the house',
  'lib/ui/calendar/labour_signs_screen.dart': 'signs of labour and when to go in',
  'lib/ui/calendar/pregnancy_warnings.dart': 'the pregnancy red-flag list',
  'lib/ui/calendar/pregnancy_weight_screen.dart':
      'grades weight gain against the IOM/RK bands by pre-pregnancy BMI',
  'lib/ui/calendar/weight_card.dart': 'weight, and progress toward a target',
  'lib/ui/calendar/antenatal_plan_screen.dart':
      'the RK MOH 8-visit antenatal protocol',
  'lib/ui/calendar/week_detail_screen.dart':
      'one pregnancy week, with the antenatal visit due in it',
  // -- Cycle, postpartum, mood ---------------------------------------------
  'lib/ui/calendar/cycle_insights_screen.dart':
      'grades cycle regularity and length',
  'lib/ui/calendar/logging_drawer.dart':
      'the symptom, flow and mood pickers — every chip is a body observation',
  'lib/ui/calendar/day_log_sheet.dart':
      'one day of symptoms, flow and mood, as she records them',
  'lib/ui/calendar/symptom_days_screen.dart':
      'one symptom across the days she logged it',
  'lib/ui/calendar/postpartum_screen.dart':
      'recovery notes, red flags, and the EPDS entry point',
  'lib/ui/calendar/epds_screen.dart':
      'the Edinburgh Postnatal Depression Scale — a validated instrument',
  // -- The child ------------------------------------------------------------
  'lib/ui/tracking/child_detail_screen.dart':
      'the child health hub: illness, vaccines, growth, solids',
  'lib/ui/tracking/child_growth_screen.dart': 'weight and length over time',
  'lib/ui/tracking/child_development_screen.dart':
      'milestones, and whether one is worth asking about',
  'lib/ui/tracking/child_illness_screen.dart':
      '«Если малыш заболел»: 38 °C under three months, red flags, aspirin',
  'lib/ui/tracking/child_emergency_screen.dart': 'the child emergency card',
  'lib/ui/tracking/child_safety_screen.dart':
      'renders the CS_ advisories — back-sleeping, car seat, choking, water',
  'lib/ui/tracking/safe_sleep_screen.dart': 'the SIDS risk-reduction rules',
  'lib/ui/tracking/home_safety_screen.dart':
      '50 °C tap water, safe sleep, choking, medicines locked',
  'lib/ui/tracking/solids_screen.dart':
      'six months, honey and botulism, choking, allergens',
  'lib/ui/tracking/teething_screen.dart': 'what teething does NOT cause',
  'lib/ui/tracking/vaccination_screen.dart': 'the national immunisation schedule',
  'lib/ui/tracking/newborn_log_screen.dart':
      'feeds, nappies and sleep in the first weeks',
  'lib/ui/tracking/night_feed_screen.dart':
      'night feeds and their timing in the first weeks',
  'lib/ui/tracking/cry_insight_screen.dart':
      'tells a mother what her baby’s cry might mean',
  // -- Authored clinical content -------------------------------------------
  'lib/ui/content/article_screen.dart':
      'the red-flag block inside an authored article',
  'lib/ui/content/guides_screen.dart':
      '«Когда сразу звонить 103» sits on this screen',
};

/// Files that render reviewed clinical copy but whose verdict colours grade
/// something OTHER than a body. Out of scope, each with the reason, because
/// dragging them in is how a guard starts crying wolf.
const _offSurfaces = <String, String>{
  'lib/ui/calendar/medications_screen.dart':
      'THE CLOSEST CALL IN THIS FILE. Mint and a tick mark a dose she recorded '
          'as taken, against a schedule she typed in herself; amber marks one '
          'that is late. The claim is about adherence to her own plan, not '
          'about her body, and the app names no consequence of missing it. If '
          'that ever changes — an overdue dose grading a risk — it moves up.',
  'lib/ui/calendar/hospital_bag_screen.dart':
      'a packing list. The tick means the nightdress is in the bag. This is '
          'the exact screen the «роддом» deny-list cried wolf on.',
  'lib/ui/tracking/alerts_screen.dart':
      'THE OTHER CLOSE CALL. It looks clinical and is not: every row is a '
          'geofence crossing, a check-in, a low battery or an SOS push from a '
          'child device. Mint means "no alert arrived", not "she is well", and '
          'the coral SOS row is a log entry about a button someone pressed, '
          'not a graded observation of a body. Pulling it in would pull in '
          'zones_screen and child_map_screen behind it, and this guard would '
          'become a guard about child SAFETY — a different subject with a '
          'different reviewer. The one thing here that could be argued in is '
          'the SOS row.',
  'lib/ui/settings/settings_screen.dart':
      'backup, import and account state; the one clinical string on it is the '
          '«не медицинский прибор» disclaimer, which has no colour',
  'lib/ui/settings/support_thread_screen.dart':
      'a support conversation: delivery state and the chat disclaimer',
  'lib/ui/home_shell.dart': 'the offline banner — a network claim',
  'lib/ui/tracking/child_today_screen.dart':
      'frame 15a\'s care list. It names the clinical screens (прививки, '
          'прикорм, безопасность дома) but grades nothing: all four tile '
          'glyphs are ONE colour on purpose, chosen so that «Стоит уточнить: '
          '3» cannot go amber — domain/vaccination.dart:126 calls that state '
          '`passed` and forbids reading it as «пропущена», and a tile that '
          'went amber for it would be making exactly that claim in colour. '
          'The single amber here is the cake glyph on «Дата рождения не '
          'указана», which grades the app\'s own missing field. If a tile ever '
          'takes its colour from a reading, this moves up.',
  'lib/ui/chat/assistant_chat_screen.dart':
      'message send state; the disclaimer above it carries no colour',
  'lib/ui/settings/help_support_screen.dart': 'help articles and contact rows',
  'lib/ui/appointments/visit_summary.dart':
      'what to bring to a visit; the colours are section identity',
  'lib/ui/calendar/cycle_summary.dart': 'a shareable summary sheet',
};

// ---------------------------------------------------------------------------
// The manifest
// ---------------------------------------------------------------------------

/// `basis` for a signal that grades nothing: identity, chrome, or a state of
/// the app rather than of a body. Still registered — the assertion "this does
/// not vary with a reading" is exactly what a reviewer should be able to check.
const _noClaim = 'NOT A CLINICAL CLAIM';

class _Sig {
  final String file;
  final String cls;
  final String token;
  final int n;

  /// What a reader is entitled to conclude from seeing this.
  final String claim;

  /// On whose authority — or why it asserts nothing.
  final String basis;

  const _Sig(this.file, this.cls, this.token, this.n,
      {required this.claim, required this.basis});

  String get key => '$file :: $cls :: $token';
}

/// Frozen at what it already draws, so it cannot drift while it waits for a
/// verdict — the `pinned 2026-08-18, UNREVIEWED` convention of the string
/// manifest, and it means exactly as little: nobody has approved this, we have
/// only written down what it says. [_pinnedCap] keeps the number honest.
const _pinned = 'PINNED 2026-08-20, UNREVIEWED';

/// The RK MOH antenatal protocol, the document `an_source` cites and the one
/// the fetal-movement ruling was decided against.
const _rkAntenatal = 'RK MOH «Антенатальный уход» (2025)';

const _entries = <_Sig>[
  // ==========================================================================
  // The vitals dashboard. Everything the wearable produces is graded here, so
  // this is where a colour is most likely to be the whole message.
  // ==========================================================================
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_specs', 'Palette.teal', 1,
      claim: 'nothing: mint is the SpO₂ tile identity colour, on every value',
      basis: '$_noClaim. `MetricSpec.color` is fixed per metric at construction '
          'and never varies with the reading. What grades a tile is '
          '`_statusColor`, registered below.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', 'HealthDashboardView', 'Palette.danger', 1,
      claim: 'nothing about her body: the dot counts unread announcements',
      basis: '$_noClaim. `Badge.count` on the notifications button.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', 'HealthDashboardView', 'Ds.pastelMint', 1,
      claim: 'nothing: the «Шевеления» quick action is mint the way the water '
          'action is blue',
      basis: '$_noClaim. A fixed `QuickAction` tint; the same tile is mint with '
          'no kicks logged and with forty.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', 'HealthDashboardView', 'Ds.mintText', 1,
      claim: 'nothing: the icon colour paired with the tint above',
      basis: '$_noClaim. `Ds.mintText` is the measured text-safe mint, chosen '
          'for contrast on `Ds.pastelMint`, not for meaning.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_PeaceOfMindBanner', 'Palette.good', 2,
      claim: 'every reading the app currently holds is inside the band it '
          'grades on — the broadest reassurance in the product',
      basis: 'REVIEWED with the watch-vitals set (docs/CLINICAL-REVIEW-WATCH.md, '
          '2026-08-13). Driven by `currentOverallStatus`, whose reassurance half '
          'is restricted to CURRENT readings after the advisor said «ничего '
          'необычного» over nine-hour-old data (domain/current_advisories.dart); '
          'each band it can reassure on is cited in packages/shared/src/triage.ts.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_PeaceOfMindBanner', 'Icons.check_rounded', 1,
      claim: 'the same all-clear, in the register the kick history lost on '
          '2026-08-19',
      basis: 'Same ruling and the same `AdviceTone` value as the banner colour '
          'above, so the tick cannot disagree with the words beside it.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_PeaceOfMindBanner', 'Palette.amber', 2,
      claim: 'something in her current readings is worth a look, and it is not '
          'an emergency',
      basis: '`AdviceTone.watch`; the advisory card underneath names which '
          'reading and why, and the amber never appears without it.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_MetricAge', 'Ds.amberText', 1,
      claim: 'this reading is old — a claim about the DATA, not about her',
      basis: '$_noClaim. Driven by `MetricFreshness`, not `MetricStatus`. '
          'c316c29 ruled that dim ink means stale; amber is the same claim '
          'where dim measured too faint to read.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_statusColor', 'Palette.teal', 1,
      claim: 'this reading is inside the band this product cites for it',
      basis: 'REVIEWED 2026-08-19 — the function carries the ruling in its own '
          'doc comment («GREEN IS A CLAIM»): mint survives only for a current '
          'reading on a cited band from a source we may reassure from. Device '
          'temperature, device glucose and device BP arrive `ungraded` and get '
          'body ink. Pinned by metric_status_test.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_statusColor', 'Palette.watch', 1,
      claim: 'this reading is outside the band but not at the emergency cutoff',
      basis: 'REVIEWED 2026-08-19. The `watch` tier was DELETED from the systolic '
          'and diastolic branches the same day because 135/85 could not be '
          'cited; what remains is cited in packages/shared/src/triage.ts.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_statusColor', 'Palette.danger', 1,
      claim: 'this reading is at or past a cutoff that means act now',
      basis: 'REVIEWED 2026-08-19. 140/90 from ACOG for blood pressure, and the '
          'rest of the cutoffs in packages/shared/src/triage.ts.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_MetricCard', 'Palette.danger', 1,
      claim: 'this whole tile is in danger — the value takes the alarm colour',
      basis: 'Reads the same `MetricStatus` as `_statusColor`; it cannot grade '
          'anything that function did not already grade.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_MetricCard', 'Palette.watch', 1,
      claim: 'this metric is trending upward, and up is the direction to watch',
      basis: '$_pinned — the trend arrow is amber for `Trend.up` on EVERY '
          'metric, including ones where up is not the worrying direction (SpO₂, '
          'sleep). Nobody has ruled on that.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_BloodPressureCard', 'Palette.danger', 1,
      claim: 'this blood-pressure pair is at or past 140/90',
      basis: 'REVIEWED 2026-08-19. The card takes `danger` only from '
          '`metricStatus`, which grades BP against 140/90 and nothing else.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_BloodPressureCard', 'Palette.watch', 1,
      claim: 'blood pressure is trending upward',
      basis: '$_pinned — the same trend arrow as `_MetricCard`, on the metric '
          'whose amber band was refused for being uncited. The arrow describes '
          'a direction of travel, not a band, which is why it survived that '
          'ruling; that reasoning has not been to the gate.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_WearableSummaryCard', 'Palette.teal', 1,
      claim: 'nothing: the badge behind the section icon',
      basis: '$_noClaim. A constant `_IconBadge` colour, identical whatever the '
          'wearable reports.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_ActivityWellnessCard', 'Palette.teal', 1,
      claim: 'nothing: steps are mint, distance blue, calories amber',
      basis: '$_noClaim. A fixed palette per statistic so the row reads as a '
          'set; no threshold anywhere in the widget.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_ActivityWellnessCard', 'Palette.watch', 1,
      claim: 'nothing: the calories statistic identity colour',
      basis: '$_noClaim. Same fixed palette as the mint above; a low or a high '
          'figure is the same amber.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_VitalsFreshness', 'Ds.amberText', 1,
      claim: 'the vitals under this line are over 24 hours old',
      basis: '$_noClaim, by the c316c29 rule: staleness is a claim about the '
          'device, and the string it colours («данные от …») says only when.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_StatusChip', 'Palette.amber', 1,
      claim: 'her period is late',
      basis: '$_pinned. The widget says in place «amber for a late period — '
          'worth a look, never an alarm red», which is a judgement written by an '
          'engineer, not a verdict from the gate. Cycle prediction is not a '
          'clinical instrument and the chip does not claim it is.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_RepeatReadingCard', 'Palette.amber', 3,
      claim: 'a reading came back off, and it is worth taking again before '
          'concluding anything',
      basis: 'The `repeat_` strings are in the reviewed manifest; the amber is '
          'the tint, icon and border of that same card, and it appears only '
          'when one of those strings does.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_AntenatalProtocolCard', 'Palette.teal', 3,
      claim: 'an antenatal test window is open for her now',
      basis: '$_rkAntenatal, transcribed verbatim in the contract and verified '
          'by tool/verify_antenatal_protocol.dart. Mint marks the window as '
          'open — a schedule, not a finding about her body.'),
  _Sig('lib/ui/dashboard/health_dashboard_screen.dart', '_WeeklyDigestCard', 'Palette.teal', 1,
      claim: 'nothing: the sleep figure in the weekly digest is mint the way '
          'the one beside it is blue',
      basis: '$_noClaim. A `_DigestStat` colour fixed per statistic; six hours '
          'and nine hours are the same mint.'),

  _Sig('lib/ui/dashboard/metric_detail_screen.dart', '_MetricDetailScreenState', 'Palette.danger', 2,
      claim: 'this reading is at or past the cutoff that means act now',
      basis: 'The same `MetricStatus` as the dashboard tile, so the detail '
          'screen cannot grade a reading the tile did not.'),
  _Sig('lib/ui/dashboard/metric_detail_screen.dart', '_MetricDetailScreenState', 'Ds.amberText', 1,
      claim: 'outside the band, below the emergency cutoff',
      basis: 'As `_statusColor`, REVIEWED 2026-08-19; the text-safe amber is '
          'the accessibility pairing, not a different tier.'),
  _Sig('lib/ui/dashboard/metric_detail_screen.dart', '_TrendChip', 'Palette.watch', 1,
      claim: 'this metric is trending upward',
      basis: '$_pinned — the same unruled trend arrow as the dashboard.'),
  _Sig('lib/ui/dashboard/metric_detail_screen.dart', '_LargeChartPainter', 'Palette.danger', 1,
      claim: 'points inside this band on the chart are the ones the app calls '
          'dangerous',
      basis: 'The band is painted from the same cited cutoffs as '
          '`MetricStatus.danger`; it draws the threshold rather than adding one.'),

  _Sig('lib/ui/dashboard/sleep_card.dart', 'sleepAccentFor', 'Palette.good', 1,
      claim: 'she slept well last night',
      basis: '$_pinned. `SleepQuality` is computed from duration alone, on hours '
          'this repo cites nowhere; the words beside it are `ADV_SLEEP_*`, which '
          'are in the reviewed manifest, but the band that picks the mint is not.'),
  _Sig('lib/ui/dashboard/sleep_card.dart', 'sleepAccentFor', 'Palette.amber', 1,
      claim: 'she slept badly last night',
      basis: '$_pinned. Same uncited band as the mint above, in the other '
          'direction.'),
  _Sig('lib/ui/dashboard/sleep_detail_screen.dart', '_ConsistencyCard', 'Palette.good', 1,
      claim: 'her bedtimes are consistent, and consistent is good',
      basis: '$_pinned. `SleepConsistency` is a spread over recent nights; the '
          'threshold is the products own and is cited nowhere.'),
  _Sig('lib/ui/dashboard/sleep_detail_screen.dart', '_ConsistencyCard', 'Icons.check_circle_rounded', 1,
      claim: 'the same verdict as a tick — the shape that outlived two copy '
          'reviews on the kick history',
      basis: '$_pinned, with the colour above; it rides the same enum value.'),
  _Sig('lib/ui/dashboard/sleep_detail_screen.dart', '_ConsistencyCard', 'Palette.amber', 1,
      claim: 'her bedtimes vary',
      basis: '$_pinned. Same uncited spread as the mint.'),
  _Sig('lib/ui/dashboard/log_sleep_sheet.dart', '_LogSleepSheetState', 'Palette.danger', 2,
      claim: 'nothing about her sleep: the times she typed do not make a night',
      basis: '$_noClaim. Form validation — an end before a start, a span over '
          '24 hours.'),
  _Sig('lib/ui/dashboard/log_sleep_sheet.dart', '_LogSleepSheetState', 'Icons.error_outline_rounded', 1,
      claim: 'nothing: the icon on that same validation message',
      basis: '$_noClaim. Shown only with the string above.'),
  _Sig('lib/ui/dashboard/water_card.dart', 'WaterCard', 'Palette.good', 2,
      claim: 'she reached today water target',
      basis: '$_pinned. The target is a fixed number of glasses in '
          'domain/water.dart, not a hydration requirement from any source, and '
          'the app names no consequence of missing it. It grades her own log '
          'against her own goal — the same shape as the kick counter, and the '
          'difference is that ten movements came from a protocol that says the '
          'count predicts nothing while this number came from us.'),
  _Sig('lib/ui/dashboard/water_card.dart', 'WaterCard', 'Icons.check_rounded', 1,
      claim: 'the target-reached tick, in the middle of the ring',
      basis: '$_pinned, with the colour above. Named separately because a tick '
          'inside a ring at a goal is, to the pixel, the thing the clinical '
          'gate removed from the kick counter on 2026-08-19.'),
  _Sig('lib/ui/dashboard/water_history_screen.dart', '_EditableDayRow', 'Palette.good', 1,
      claim: 'this day reached the target',
      basis: '$_pinned. The same goal as `WaterCard`, per day.'),
  _Sig('lib/ui/dashboard/water_history_screen.dart', '_DayBar', 'Palette.good', 1,
      claim: 'this bar reached the target',
      basis: '$_pinned. The same goal again, in the chart.'),

  _Sig('lib/ui/calibration/bp_calibration_sheet.dart', '_CalibrateBodyState', 'Palette.watch', 2,
      claim: 'nothing about her blood pressure: the band is not reporting a '
          'waveform, so calibration cannot start',
      basis: '$_noClaim. `cal_no_band` — a device state.'),
  _Sig('lib/ui/calibration/bp_calibration_sheet.dart', '_CalibrateBodyState', 'Palette.danger', 3,
      claim: 'the cuff figures she typed are too far from the wrist reading to '
          'calibrate against — the app is refusing HER INPUT, not grading her',
      basis: '$_noClaim. `cal_too_far`, a plausibility bound on the pair being '
          'entered. Registered anyway because coral over two blood-pressure '
          'numbers is one glance away from reading as a verdict on them.'),
  _Sig('lib/ui/calibration/bp_calibration_sheet.dart', '_CalibrateBodyState', 'Icons.error_outline_rounded', 1,
      claim: 'the icon on that same rejection',
      basis: '$_noClaim. Shown only with `cal_too_far`.'),

  // ==========================================================================
  // The advisory pipeline — the surface the whole clinical review began on.
  // ==========================================================================
  _Sig('lib/ui/advisor/advisor_screen.dart', 'AdvisorScreen', 'Palette.teal', 1,
      claim: 'nothing: the sparkle beside the screen title',
      basis: '$_noClaim. A constant header icon.'),
  _Sig('lib/ui/advisor/advisor_screen.dart', '_AskCard', 'Palette.teal', 2,
      claim: 'nothing: the «ask a question» card is mint',
      basis: '$_noClaim. A constant tint and icon on an entry point to the chat.'),
  _Sig('lib/ui/advisor/advisor_screen.dart', '_AdvisoryCard', 'Palette.good', 1,
      claim: 'this advisory is a reassurance — nothing here needs attention',
      basis: 'REVIEWED 2026-08-19, and narrowed by that sitting: `ADV_BP_STEADY` '
          'was DELETED rather than recoloured because no band could be cited for '
          '«давление ровное» (docs/CLINICAL-REVIEW-WATCH.md). Every card that can '
          'still be `AdviceTone.positive` has its text in the reviewed manifest.'),
  _Sig('lib/ui/advisor/advisor_screen.dart', '_AdvisoryCard', 'Icons.check_circle_outline', 1,
      claim: 'the tick that comes with that reassurance',
      basis: 'Same tone value and same ruling as the mint above.'),
  _Sig('lib/ui/advisor/advisor_screen.dart', '_AdvisoryCard', 'Palette.watch', 1,
      claim: 'this advisory is a watch — worth attention, not an emergency',
      basis: 'The `ADV_*` bodies are fingerprinted in the reviewed manifest and '
          'the seek-help clause on the red-flag ones is enforced by '
          'red_flag_copy_test.'),
  _Sig('lib/ui/advisor/advisory_body.dart', 'RedFlagBlock', 'Palette.amber', 1,
      claim: 'what follows is a red flag: call if you see it',
      basis: 'The block is only built for authored red-flag text, and '
          'red_flag_copy_test enforces that such text names who to call.'),
  _Sig('lib/ui/advisor/advisory_body.dart', 'RedFlagBlock', 'Ds.amberText', 2,
      claim: 'the text and heading colour of that same red-flag block',
      basis: 'The measured text-safe amber; the accessibility pairing for the '
          'fill above, not a second tier.'),
  _Sig('lib/ui/advisor/advisory_body.dart', 'RedFlagBlock', 'Icons.priority_high_rounded', 1,
      claim: 'the same red flag, in the icon register',
      basis: 'Drawn only inside the block above.'),

  // ==========================================================================
  // Emergency
  // ==========================================================================
  _Sig('lib/ui/emergency/emergency_help_screen.dart', '_CallCard', 'Ds.sos', 1,
      claim: 'this is the call-103 card',
      basis: 'The `eh_` strings are pinned in the reviewed manifest and the '
          'screen is generated from emergency_help.json, verified by '
          'tool/verify_emergency_help_contract.dart.'),
  _Sig('lib/ui/emergency/emergency_help_screen.dart', '_ScenarioCard', 'Ds.sos', 1,
      claim: 'this scenario is the red tier: call an ambulance',
      basis: 'The severity comes from the contract file, not from the widget; '
          'the same runner checks that every red scenario has one.'),
  _Sig('lib/ui/emergency/emergency_help_screen.dart', '_ScenarioCard', 'Ds.amber', 1,
      claim: 'this scenario is the amber tier: be seen, not necessarily by 103',
      basis: 'Same contract, same runner.'),
  _Sig('lib/ui/emergency/emergency_help_screen.dart', '_ScenarioCard', 'Ds.amberText', 2,
      claim: 'the text colour of an amber-tier scenario',
      basis: 'The accessibility pairing for the stripe above.'),
  _Sig('lib/ui/emergency/emergency_rescue_screen.dart', '_EmergencyRescueScreenState', 'Palette.danger', 1,
      claim: 'this screen is about calling an ambulance',
      basis: 'A screen-wide accent on the confirmation gate; it grades nothing, '
          'but it is the loudest colour in the product and belongs on the record.'),
  _Sig('lib/ui/emergency/emergency_rescue_screen.dart', '_EmergencyRescueScreenState', 'Icons.warning_amber_rounded', 1,
      claim: 'the icon over the «this calls 103» confirmation',
      basis: 'The `em_` gate copy is pinned in the reviewed manifest.'),
  _Sig('lib/ui/tracking/sos_alert_screen.dart', '_SosAlertScreenState', 'Ds.sos', 1,
      claim: 'a child of hers has pressed SOS',
      basis: '$_noClaim about a body. The screen reports an event and offers '
          'the actions; nothing here is a reading.'),
  _Sig('lib/ui/tracking/sos_alert_screen.dart', '_ActionButton', 'Ds.sos', 3,
      claim: 'the call and dismiss buttons on that alert',
      basis: '$_noClaim. Button chrome in the screen accent.'),

  // ==========================================================================
  // Pregnancy, cycle, postpartum
  // ==========================================================================
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_WomensHealthScreenState', 'Icons.check_rounded', 1,
      claim: 'nothing: today period is already logged, so the button says so',
      basis: '$_noClaim. It reflects her own entry back to her; the icon '
          'changes with the log, not with any grade of it.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_PhasePill', 'Palette.teal', 2,
      claim: 'this day is in the fertile window or is the predicted ovulation',
      basis: '$_pinned. A predicted phase from her own logged dates; '
          '`cyc_share_disclaimer` and `phase_fertile_note` — both in the '
          'reviewed manifest — say it is not contraception.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_MonthCalendar', 'Palette.amber', 1,
      claim: 'nothing clinical: there is an appointment on this day',
      basis: '$_noClaim. A 6px dot marking a diary entry.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', 'cycleCellStyle', 'Palette.teal', 3,
      claim: 'the fertile/ovulation days on the month grid',
      basis: '$_pinned, with `_PhasePill` — the same prediction, drawn on the '
          'calendar instead of in a pill.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_HospitalBagCard', 'Icons.check_circle_rounded', 1,
      claim: 'nothing: the bag is packed',
      basis: '$_noClaim. A packing list, the «Сумка в роддом» case.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_HospitalBagCard', 'Palette.teal', 1,
      claim: 'nothing: the same packed state, in colour',
      basis: '$_noClaim. As above.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_CyclePhaseCard', 'Palette.teal', 1,
      claim: 'she is in the fertile phase today',
      basis: '$_pinned. The phase note beside it (`phase_fertile_note`) is in '
          'the reviewed manifest; the colour is the phase identity.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_CyclePhaseCard', 'Palette.amber', 1,
      claim: 'she is in the luteal phase today',
      basis: '$_pinned. A phase identity colour, not a grade of it — luteal is '
          'not «worse» than follicular, and amber here does not mean watch.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_UsualSymptomsCard', 'Palette.amber', 4,
      claim: 'these are the symptoms she usually logs at this point',
      basis: '$_pinned. A card-wide tint over her own history; the card makes '
          'no claim about whether any of it is normal.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_FertileCountdownCard', 'Palette.teal', 4,
      claim: 'the fertile window is coming or open',
      basis: '$_pinned, with the other fertile-window mint on this screen.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_CyclePredictions', 'Palette.amber', 1,
      claim: 'her period is late by n days',
      basis: '$_pinned, and it is the same claim as `_StatusChip` on the '
          'dashboard. Late against a PREDICTION, which the confidence chip two '
          'entries down admits may be poor.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_CyclePredictions', 'Palette.teal', 2,
      claim: 'the fertile-window and ovulation rows of the prediction list',
      basis: '$_pinned. Row identity colours matching the phase pills.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_ConfidenceChip', 'Palette.amber', 2,
      claim: 'these predictions are rough — either still building or her cycle '
          'varies too much',
      basis: 'A claim about the DATA, and a deliberately cautious one: the '
          'widget notes in place that `variable` is amber like `building` '
          'because the date is equally approximate.'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_ConfidenceChip', 'Palette.good', 1,
      claim: 'these predictions are reliable',
      basis: '$_pinned. A claim about the prediction, not about her body — but '
          'it is mint on a cycle screen and `cyc_share_disclaimer` is the only '
          'thing keeping «reliable» from reading as «this is a test».'),
  _Sig('lib/ui/calendar/womens_health_screen.dart', '_CycleLegend', 'Palette.teal', 2,
      claim: 'nothing: the legend swatch for the fertile days',
      basis: '$_noClaim. It defines the calendar colours rather than applying '
          'one to a day.'),

  _Sig('lib/ui/calendar/contraction_timer_screen.dart', '_Criterion', 'Ds.mint', 1,
      claim: 'this part of the 5-1-1 rule is met right now',
      basis: 'The `contr_511_` strings are pinned in the reviewed manifest and '
          'the rule is computed in domain code verified by '
          'tool/verify_contractions.dart. Mint marks one CRITERION met, never '
          '«go in» — the go decision needs all three and says so in words.'),
  _Sig('lib/ui/calendar/contraction_timer_screen.dart', '_Criterion', 'Icons.check_circle_rounded', 1,
      claim: 'the same criterion, ticked',
      basis: 'Same computation as the mint above. This is the one place in the '
          'app where a tick on a timed body event is intended, and it is '
          'per-criterion for exactly that reason.'),
  _Sig('lib/ui/calendar/pregnancy_warnings.dart', 'PregnancyWarningsCard', 'Icons.warning_amber_rounded', 1,
      claim: 'what follows is a pregnancy red-flag list',
      basis: 'The `preg_warn_` strings are pinned in the reviewed manifest; the '
          'icon labels the list, it does not select anything.'),
  _Sig('lib/ui/calendar/pregnancy_weight_screen.dart', 'PregnancyWeightScreen', 'Palette.teal', 1,
      claim: 'her weight gain is on track for her pre-pregnancy BMI band',
      basis: '$_pinned. `GainPace.onTrack` against the `pwg_` ranges, which are '
          'pinned in the reviewed manifest but whose source is not named on the '
          'screen. A positive verdict on a body measurement — the shape the '
          'kick ruling was about.'),
  _Sig('lib/ui/calendar/pregnancy_weight_screen.dart', 'PregnancyWeightScreen', 'Icons.check_circle_outline', 1,
      claim: 'the same on-track verdict, as a tick',
      basis: '$_pinned, with the mint above; same `GainPace` value.'),
  _Sig('lib/ui/calendar/weight_card.dart', '_TargetRow', 'Palette.good', 2,
      claim: 'she has reached the weight target she set',
      basis: '$_pinned. The number is HERS — typed into the target sheet, not '
          'derived by us — which is what separates this mint from the kick ring, '
          'where the goal was ours and the protocol behind it says the count '
          'predicts nothing. Recorded so a reviewer can disagree.'),
  _Sig('lib/ui/calendar/weight_card.dart', '_WeightTargetSheetState', 'Palette.danger', 1,
      claim: 'nothing: the «clear target» button is a destructive action',
      basis: '$_noClaim. Confirm-and-delete chrome.'),
  _Sig('lib/ui/calendar/antenatal_plan_screen.dart', '_LeadCard', 'Palette.teal', 1,
      claim: 'the next antenatal visit is not due yet',
      basis: '$_rkAntenatal, verbatim in the contract; coral marks due-now and '
          'mint marks not-yet, which is a schedule state.'),
  _Sig('lib/ui/calendar/antenatal_plan_screen.dart', '_TermCard', 'Palette.teal', 1,
      claim: 'the pregnancy has reached term',
      basis: '$_rkAntenatal — `an_term_title` / `an_term_note`, both pinned in '
          'the reviewed manifest. Term is a gestational fact, not a grade of '
          'how the pregnancy is going.'),
  _Sig('lib/ui/calendar/antenatal_plan_screen.dart', '_TermCard', 'Icons.verified_rounded', 1,
      claim: 'the same term milestone, as a badge',
      basis: 'Drawn only inside the card above. A `verified` badge is a strong '
          'shape for a date arithmetic result, and that is why it is here.'),
  _Sig('lib/ui/calendar/antenatal_plan_screen.dart', '_catColour', 'Palette.teal', 2,
      claim: 'nothing: counselling and prophylaxis items are mint, labs blue',
      basis: '$_noClaim. A fixed colour per protocol category.'),
  _Sig('lib/ui/calendar/week_detail_screen.dart', '_areaColour', 'Palette.teal', 1,
      claim: 'nothing: the «your body» section of a pregnancy week',
      basis: '$_noClaim. A fixed colour per content area.'),
  _Sig('lib/ui/calendar/week_detail_screen.dart', '_WeekCalendarCard', 'Icons.check_circle_outline', 1,
      claim: 'nothing about her: the row heading for «recommended this week»',
      basis: '$_noClaim. A bullet on authored content, drawn whether or not she '
          'has done any of it.'),
  _Sig('lib/ui/calendar/week_detail_screen.dart', '_AntenatalCard', 'Palette.teal', 1,
      claim: 'the antenatal visit for this week is not due yet',
      basis: 'The same due/not-due split as `_LeadCard`, from the same protocol.'),

  _Sig('lib/ui/calendar/cycle_insights_screen.dart', 'CycleInsightsScreen', 'Palette.amber', 1,
      claim: 'nothing: the symptom-frequency rows are amber',
      basis: '$_noClaim. A fixed row colour over counts of her own logs.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', 'CycleInsightsScreen', 'Palette.teal', 1,
      claim: 'nothing: the mood-frequency rows are mint',
      basis: '$_noClaim. As above, for the mood table.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', '_StreakBanner', 'Palette.amber', 2,
      claim: 'nothing clinical: she has logged n days in a row',
      basis: '$_noClaim. An engagement streak.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', '_CycleLengthCard', 'Palette.teal', 1,
      claim: 'nothing: the average-cycle-length figure',
      basis: '$_noClaim. The card states a number she can check; the grading of '
          'it is `_RegularityCard`, next.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', '_RegularityCard', 'Palette.good', 1,
      claim: 'her cycles are regular',
      basis: '$_pinned. `CycleRegularity.regular` from a spread threshold in '
          'domain code, cited to nothing, published as mint plus a tick. The '
          'strongest unreviewed reassurance this manifest found outside the '
          'vitals pipeline.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', '_RegularityCard', 'Icons.check_circle_rounded', 1,
      claim: 'the same regularity verdict, as a tick',
      basis: '$_pinned, with the mint above.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', '_RegularityCard', 'Palette.amber', 1,
      claim: 'her cycles vary',
      basis: '$_pinned. The other side of the same uncited threshold; the '
          'irregular tier is coral and is not in this list because it is '
          '`Palette.roseDeep`, the brand accent — see the note on colour names '
          'at the top of this file.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', '_CycleRow', 'Palette.teal', 1,
      claim: 'nothing: this cycle is the one still running',
      basis: '$_noClaim. Mint marks the open row, ink marks a finished one.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', 'moodColor', 'Palette.amber', 1,
      claim: 'nothing: «happy» is amber',
      basis: '$_noClaim. A fixed colour per mood, shared with the logging '
          'drawer so one feeling is not two colours in two places.'),
  _Sig('lib/ui/calendar/cycle_insights_screen.dart', 'moodColor', 'Palette.teal', 1,
      claim: 'nothing: «calm» is mint',
      basis: '$_noClaim. As above.'),
  _Sig('lib/ui/calendar/logging_drawer.dart', 'moodStyle', 'Palette.good', 1,
      claim: 'nothing: «happy» is mint in the picker',
      basis: '$_noClaim. The same table, public so the postpartum screen cannot '
          'drift from it. Mint is not «the good mood to have».'),
  _Sig('lib/ui/calendar/logging_drawer.dart', 'moodStyle', 'Palette.teal', 1,
      claim: 'nothing: «calm» is teal in the picker',
      basis: '$_noClaim. As above.'),
  _Sig('lib/ui/calendar/logging_drawer.dart', 'moodStyle', 'Palette.amber', 1,
      claim: 'nothing: «anxious» is amber in the picker',
      basis: '$_noClaim — and the one to argue about, since amber elsewhere in '
          'this app means watch. It is an identity colour in a fixed table; '
          'nothing reads it back as a grade.'),
  _Sig('lib/ui/calendar/logging_drawer.dart', '_symptomStyle', 'Palette.good', 1,
      claim: 'nothing: a symptom chip colour',
      basis: '$_noClaim. One fixed colour per symptom so the chips are '
          'distinguishable; no symptom is ranked against another.'),
  _Sig('lib/ui/calendar/logging_drawer.dart', '_symptomStyle', 'Palette.amber', 1,
      claim: 'nothing: the cramps chip colour',
      basis: '$_noClaim. As above.'),
  _Sig('lib/ui/calendar/logging_drawer.dart', '_symptomStyle', 'Palette.teal', 1,
      claim: 'nothing: the nausea chip colour',
      basis: '$_noClaim. As above.'),
  _Sig('lib/ui/calendar/logging_drawer.dart', '_flowStyle', 'Palette.danger', 1,
      claim: 'nothing: heavy flow is the darkest of three drops',
      basis: '$_noClaim, and deliberately so: the three flow levels are a ramp, '
          'and coral is its dark end. The app does not say heavy flow is '
          'abnormal — `pp_warn_` and `preg_warn_` do that in words, with a '
          'threshold.'),

  _Sig('lib/ui/calendar/postpartum_screen.dart', '_MoodSection', 'Icons.check_circle_outline', 1,
      claim: 'nothing: today mood is recorded',
      basis: '$_noClaim. It reflects her own entry; no mood is the right one.'),
  _Sig('lib/ui/calendar/postpartum_screen.dart', '_MoodSection', 'Palette.good', 2,
      claim: 'nothing: the same «recorded» state, in colour',
      basis: '$_noClaim. Mint when a mood exists, dim when none does — a '
          'presence check, not a reading of the mood.'),
  _Sig('lib/ui/calendar/postpartum_screen.dart', '_ScreeningCard', 'Palette.amber', 1,
      claim: 'her EPDS score is raised',
      basis: 'The Edinburgh scale — every `epds_` string is in the reviewed '
          'manifest and the scoring is verified by tool/verify_epds.dart. Amber '
          'is the instrument speaking, not the widget; the words say what to do.'),
  _Sig('lib/ui/calendar/postpartum_screen.dart', '_ScreeningCard', 'Ds.amberText', 1,
      claim: 'the text colour of that same raised score',
      basis: 'The accessibility pairing for the accent above.'),
  _Sig('lib/ui/calendar/postpartum_screen.dart', '_areaColour', 'Palette.teal', 1,
      claim: 'nothing: the «body» recovery area',
      basis: '$_noClaim. A fixed colour per section, matching week_detail.'),
  _Sig('lib/ui/calendar/postpartum_screen.dart', 'PostpartumWarningBlock', 'Icons.warning_amber_rounded', 1,
      claim: 'what follows is a postpartum red-flag list',
      basis: 'The `pp_warn_` strings are pinned in the reviewed manifest; the '
          'icon labels the list.'),

  // ==========================================================================
  // The child
  // ==========================================================================
  _Sig('lib/ui/tracking/child_detail_screen.dart', 'ChildDetailScreen', 'Palette.good', 1,
      claim: 'nothing clinical: a place pin beside a zone he visited',
      basis: '$_noClaim. Location history on the child hub.'),
  _Sig('lib/ui/tracking/child_growth_screen.dart', 'ChildGrowthScreen', 'Palette.teal', 1,
      claim: 'nothing: the weight statistic identity colour',
      basis: '$_noClaim. Fixed per statistic in the header row.'),
  _Sig('lib/ui/tracking/child_growth_screen.dart', '_GrowthCard', 'Palette.good', 1,
      claim: 'the child has gained weight since the last measurement, and that '
          'is good',
      basis: '$_pinned, AND FLAGGED. Any delta >= 0 is mint whatever its size '
          'and whatever the interval; nothing is compared to a growth chart '
          '(`grw_no_percentiles` says the app has none). This is a positive '
          'clinical claim on a child growth measurement from arithmetic alone.'),
  _Sig('lib/ui/tracking/child_growth_screen.dart', '_GrowthCard', 'Palette.watch', 1,
      claim: 'the child has lost weight since the last measurement, and that is '
          'worth watching',
      basis: '$_pinned, AND FLAGGED. The widget own comment says babies do lose '
          'weight in the first days and after illness — and then colours every '
          'loss amber. Either the colour or the comment is wrong; the gate '
          'should say which.'),
  _Sig('lib/ui/tracking/child_development_screen.dart', 'ChildDevelopmentTimeline', 'Ds.pastelMint', 1,
      claim: 'nothing: a section tint on the timeline',
      basis: '$_noClaim. A pale card fill, constant.'),
  _Sig('lib/ui/tracking/child_development_screen.dart', '_GrowthWeekCardState', 'Palette.teal', 1,
      claim: 'nothing: the growth statistic identity colour',
      basis: '$_noClaim. As on the growth screen.'),
  _Sig('lib/ui/tracking/child_development_screen.dart', '_MilestoneCard', 'Palette.amber', 1,
      claim: 'this milestone is worth asking a doctor about',
      basis: 'The `dev_` copy is in the reviewed manifest, including '
          '`dev_spread` («children vary») and `dev_ask_note`. `DevStatus` comes '
          'from the baby-development contract, verified by '
          'tool/verify_child_development.dart.'),
  _Sig('lib/ui/tracking/child_illness_screen.dart', 'ChildIllnessScreen', 'Icons.priority_high_rounded', 1,
      claim: 'what follows is the «call now» list for a sick baby',
      basis: 'Every `ill_` string is pinned in the reviewed manifest — 38 °C '
          'under three months, the red flags, aspirin.'),
  _Sig('lib/ui/tracking/child_illness_screen.dart', 'ChildIllnessScreen', 'Icons.warning_amber_rounded', 1,
      claim: 'what follows is the second red-flag list on that screen',
      basis: 'As above; the icons label authored sections and select nothing.'),
  _Sig('lib/ui/tracking/child_illness_screen.dart', '_CareRow', 'Palette.teal', 1,
      claim: 'nothing about her child: a bullet in the «what helps» list',
      basis: '$_noClaim. Drawn on every row of authored advice, always.'),
  _Sig('lib/ui/tracking/child_illness_screen.dart', '_CareRow', 'Icons.check_circle_outline', 1,
      claim: 'the same bullet, as a tick',
      basis: '$_noClaim. A list marker on authored text — it does not mean the '
          'reader has done it.'),
  _Sig('lib/ui/tracking/child_emergency_screen.dart', '_ContactCard', 'Palette.teal', 1,
      claim: 'nothing: the «call» button on an emergency contact',
      basis: '$_noClaim. Button chrome; `ei_disclaimer` says the card is '
          'unverified.'),
  _Sig('lib/ui/tracking/child_safety_screen.dart', 'ChildSafetyScreen', 'Palette.teal', 1,
      claim: 'nothing: the shield beside the screen title',
      basis: '$_noClaim. A constant header icon.'),
  _Sig('lib/ui/tracking/child_safety_screen.dart', '_TipCard', 'Palette.good', 1,
      claim: 'this safety tip is a reassurance rather than a warning',
      basis: 'The `CS_` cards are pinned in the reviewed manifest and their '
          'tone comes with the card, not from the widget.'),
  _Sig('lib/ui/tracking/child_safety_screen.dart', '_TipCard', 'Icons.check_circle_outline', 1,
      claim: 'the tick on that same positive tip',
      basis: 'Same tone value as the mint above.'),
  _Sig('lib/ui/tracking/child_safety_screen.dart', '_TipCard', 'Palette.amber', 1,
      claim: 'this safety tip is a watch',
      basis: 'Same `CS_` cards; the watch tier is where car seats, choking and '
          'water sit.'),
  _Sig('lib/ui/tracking/child_safety_screen.dart', '_TipCard', 'Palette.teal', 1,
      claim: 'this safety tip is neutral information',
      basis: '$_noClaim. The `info` tone — mint as the neutral card colour, '
          'which is a poor choice of pixel and is on the record for that.'),
  _Sig('lib/ui/tracking/safe_sleep_screen.dart', '_RuleRow', 'Palette.teal', 1,
      claim: 'this safe-sleep rule is a DO — the coral rows are the do-nots',
      basis: '$_noClaim about her baby: `follow` is a property of the authored '
          'rule, not of anything she has done. Every `ss_` string is pinned in '
          'the reviewed manifest and the list is the SIDS risk-reduction set.'),
  _Sig('lib/ui/tracking/safe_sleep_screen.dart', '_RuleRow', 'Icons.check_circle_outline', 1,
      claim: 'the same do/do-not split, as a tick against a cross',
      basis: '$_noClaim. Same `follow` flag as the colour above.'),
  _Sig('lib/ui/tracking/home_safety_screen.dart', 'HomeSafetyScreen', 'Palette.teal', 4,
      claim: 'she has ticked every home-safety task',
      basis: '$_pinned. The `hs_` copy is pinned in the reviewed manifest, but '
          'mint on «all done» reads as «your home is safe» when what it knows '
          'is that a checklist is full.'),
  _Sig('lib/ui/tracking/home_safety_screen.dart', 'HomeSafetyScreen', 'Icons.verified_rounded', 1,
      claim: 'the same all-done state, as a verified badge',
      basis: '$_pinned, with the mint above. `verified` is the strongest badge '
          'in the icon set and it is being spent on a self-reported checklist.'),
  _Sig('lib/ui/tracking/home_safety_screen.dart', '_TaskRow', 'Icons.check_circle_rounded', 1,
      claim: 'nothing: she ticked this task',
      basis: '$_noClaim. Her own entry, reflected back.'),
  _Sig('lib/ui/tracking/home_safety_screen.dart', '_TaskRow', 'Palette.teal', 1,
      claim: 'nothing: the same ticked state, in colour',
      basis: '$_noClaim. As above.'),
  _Sig('lib/ui/tracking/solids_screen.dart', 'SolidsScreen', 'Palette.teal', 2,
      claim: 'nothing: the header icon and its tint',
      basis: '$_noClaim. Constant chrome.'),
  _Sig('lib/ui/tracking/solids_screen.dart', '_CheckRow', 'Palette.teal', 1,
      claim: 'nothing: a bullet on authored solids guidance',
      basis: '$_noClaim. Every row has one; the `sol_` text is pinned in the '
          'reviewed manifest.'),
  _Sig('lib/ui/tracking/solids_screen.dart', '_CheckRow', 'Icons.check_circle_outline', 1,
      claim: 'the same bullet, as a tick',
      basis: '$_noClaim. A list marker, not a state.'),
  _Sig('lib/ui/tracking/teething_screen.dart', '_CheckRow', 'Palette.teal', 1,
      claim: 'nothing: a bullet on authored teething guidance',
      basis: '$_noClaim. As on the solids screen; `teeth_not_` is pinned.'),
  _Sig('lib/ui/tracking/teething_screen.dart', '_CheckRow', 'Icons.check_circle_outline', 1,
      claim: 'the same bullet, as a tick',
      basis: '$_noClaim. A list marker.'),
  _Sig('lib/ui/tracking/vaccination_screen.dart', '_VaccineRow', 'Palette.teal', 3,
      claim: 'this vaccination is recorded as given',
      basis: 'The national immunisation schedule, verified by '
          'tool/verify_vaccination_contract.dart. Mint states a record, not '
          'that the child is protected.'),
  _Sig('lib/ui/tracking/vaccination_screen.dart', '_VaccineRow', 'Palette.watch', 2,
      claim: 'this vaccination is due now',
      basis: 'The same schedule; due is a date, and `vac_catchup` covers the '
          'late case in words.'),
  _Sig('lib/ui/tracking/vaccination_screen.dart', '_VaccineRow', 'Icons.check_circle_rounded', 1,
      claim: 'the same given state, as a tick',
      basis: 'Reads the same `done` flag as the mint above.'),
  _Sig('lib/ui/tracking/newborn_log_screen.dart', 'NewbornLogScreen', 'Palette.teal', 1,
      claim: 'nothing: the feeds statistic identity colour',
      basis: '$_noClaim. Fixed per column of the log.'),
  _Sig('lib/ui/tracking/newborn_log_screen.dart', '_DayRow', 'Palette.teal', 1,
      claim: 'nothing: the wet-nappy count identity colour',
      basis: '$_noClaim, and worth stating because wet nappies ARE a clinical '
          'sign of feeding adequacy: the app counts them and grades them '
          'nowhere. Mint here is the column colour at every count, including '
          'zero.'),
  _Sig('lib/ui/tracking/cry_insight_screen.dart', '_CryInsightScreenState', 'Palette.danger', 3,
      claim: 'nothing about the baby: the microphone was denied, the analysis '
          'failed, or the clip was not sent',
      basis: '$_noClaim. Three app states. `cry_disclaimer` («подсказка, а не '
          'диагноз») governs what the screen may say about the baby.'),
  _Sig('lib/ui/tracking/cry_insight_screen.dart', '_VerdictCard', 'Palette.danger', 1,
      claim: 'nothing about the baby: this result never reached the server',
      basis: '$_noClaim. The failed-send marker on a saved result — the '
          '«assumes the request succeeded» rule, not a cry verdict.'),

  // ==========================================================================
  // Authored clinical content
  // ==========================================================================
  _Sig('lib/ui/content/article_screen.dart', '_RedFlagBlock', 'Ds.amber', 1,
      claim: 'what follows in this article is a red flag',
      basis: '`art_red_flag` is pinned in the reviewed manifest; the block is '
          'built only from authored red-flag content.'),
  _Sig('lib/ui/content/article_screen.dart', '_RedFlagBlock', 'Icons.warning_amber_rounded', 1,
      claim: 'the same red flag, in the icon register',
      basis: 'Drawn only inside that block.'),
  _Sig('lib/ui/content/article_screen.dart', '_RedFlagBlock', 'Ds.amberText', 2,
      claim: 'the text colour of that red-flag block',
      basis: 'The accessibility pairing for the fill.'),
  _Sig('lib/ui/content/guides_screen.dart', '_topicColor', 'Ds.pastelMint', 1,
      claim: 'nothing: guides about the child are tinted mint',
      basis: '$_noClaim. A fixed tint per content topic.'),
  _Sig('lib/ui/content/guides_screen.dart', '_RedFlagCard', 'Ds.amber', 1,
      claim: 'this card is «Когда сразу звонить 103»',
      basis: '`gd_call_title` / `gd_call_body` are pinned in the reviewed '
          'manifest.'),
  _Sig('lib/ui/content/guides_screen.dart', '_RedFlagCard', 'Icons.warning_amber_rounded', 1,
      claim: 'the same card, in the icon register',
      basis: 'Drawn only on that card.'),
  _Sig('lib/ui/content/guides_screen.dart', '_RedFlagCard', 'Ds.amberText', 3,
      claim: 'the text and chevron colours of that same card',
      basis: 'The accessibility pairing for the fill above.'),
];

/// How many registrations carry no verdict, only a freeze. THIS NUMBER MAY GO
/// DOWN AND NOT UP: a new clinical colour is a decision somebody is making
/// today, and «pinned, unreviewed» is only honest for what was already live on
/// 2026-08-20 when the manifest was seeded. Lowering it is what a gate sitting
/// looks like from here.
const _pinnedCap = 32;

/// A drawn verdict the clinical gate RULED OUT. Not merely unregistered:
/// refused. The count must be zero, and the failure says whose ruling it was
/// — because "register it with a reason" is the wrong instruction for these
/// two, and a generic message would invite exactly that.
///
/// `cls` may be `*` for "anywhere in this file".
class _Refusal {
  final String file;
  final String cls;
  final String token;
  final String why;
  const _Refusal(this.file, this.cls, this.token, this.why);
}

const _kickRuling = 'REFUSED 2026-08-19 (docs/CLINICAL-REVIEW-WATCH.md, '
    '«kick_goal_reached — REFUSED as written»). The RK MOH protocol this screen '
    'cites says there is no evidence that counting movements prevents adverse '
    'perinatal outcomes, so the app may not publish a verdict on the count — in '
    'words OR in colour.';

const _refused = <_Refusal>[
  // All three names for the same mint, because the ruling was about the pixel
  // and not about the identifier: `Palette.good` is what was there,
  // `Palette.teal` and `Ds.mint` are the same colour under other names.
  _Refusal('lib/ui/calendar/kick_session_screen.dart', '*', 'Palette.good',
      'The ring and the disc turned mint at ten movements. $_kickRuling '
      'Stripping the words and leaving the mint would have MOVED the claim, not '
      'removed it. The counter is `Ds.coralCta` throughout — the control own '
      'colour — and the filled ring still shows the count against ten.'),
  _Refusal('lib/ui/calendar/kick_session_screen.dart', '*', 'Palette.teal',
      'Mint on the kick counter, under the other name for the same pixel. '
      '$_kickRuling'),
  _Refusal('lib/ui/calendar/kick_session_screen.dart', '*', 'Ds.mint',
      'Mint on the kick counter, under the design-system name for the same '
      'pixel. $_kickRuling'),
  _Refusal('lib/ui/calendar/womens_health_screen.dart', '_KickHistoryRow', 'Palette.good',
      'Every saved session with ten or more movements ended in a green tick. '
      '$_kickRuling It carried no string, so no fingerprint and no token guard '
      'could ever have caught it. Nothing takes its place: the row already '
      'states the count and how long it took.'),
  _Refusal('lib/ui/calendar/womens_health_screen.dart', '_KickHistoryRow', 'Palette.teal',
      'The same tick, in the other name for mint. $_kickRuling'),
  _Refusal('lib/ui/calendar/womens_health_screen.dart', '_KickHistoryRow', 'Icons.check_rounded',
      'The tick itself, whatever colour it is drawn in. $_kickRuling'),
];

// ---------------------------------------------------------------------------
// The scanner
// ---------------------------------------------------------------------------

class _Site {
  final String file;
  final String cls;
  final String token;
  final int line;
  final String source;
  const _Site(this.file, this.cls, this.token, this.line, this.source);

  String get key => '$file :: $cls :: $token';
}

/// Blanks comments and string literals, keeping every newline and offset, so
/// line numbers survive and a token inside a comment or a string is not a
/// signal. The kick screen is the proof this is needed: its only occurrence of
/// `Palette.good` is the comment explaining why the mint is gone.
String _blankCommentsAndStrings(String src) {
  final b = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < src.length && src[i] != '\n') {
        b.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      b.write('  ');
      i += 2;
      while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        b.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < src.length) {
        b.write('  ');
        i += 2;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final triple = src.startsWith(c * 3, i);
      final delim = triple ? c * 3 : c;
      b.write(' ' * delim.length);
      i += delim.length;
      while (i < src.length) {
        if (src[i] == '\\') {
          b.write('  ');
          i += 2;
          continue;
        }
        if (src.startsWith(delim, i)) {
          b.write(' ' * delim.length);
          i += delim.length;
          break;
        }
        if (!triple && src[i] == '\n') break; // unterminated: bail, keep the newline
        b.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    b.write(c);
    i++;
  }
  return b.toString();
}

/// The enclosing declaration, which is what a registration is keyed on.
///
/// Dart has no nested types, so anything at column 0 opens a new one and every
/// member is indented under it. Both patterns are anchored there. The second
/// exists because `_statusColor` — the function that decides whether a vitals
/// tile is mint, amber or coral — is a TOP-LEVEL function declared after the
/// class that calls it, and a class-only tracker filed its three lines under
/// whichever widget happened to be above them. A key that names the wrong
/// widget is a key nobody can review.
final _typeDecl = RegExp(
  r'^(?:abstract\s+|base\s+|final\s+|sealed\s+|interface\s+)*'
  r'(?:class|mixin|extension|enum)\s+([A-Za-z_$][\w$]*)',
);
final _topLevelDecl = RegExp(
  r'^(?:final\s+|const\s+|var\s+|late\s+)*'
  r'(?:[A-Za-z_$][\w$<>,.\s?]*\s+)?([A-Za-z_$][\w$]*)\s*(?:\(|=[^=])',
);

/// `({IconData icon, Color color}) moodStyle(Mood m) => …` — a record return
/// type starts the line with a bracket, and both patterns above miss it. Three
/// of the mood/symptom tables in this app are declared exactly that way.
final _recordReturnDecl = RegExp(r'^\([^)]*\)\s+([A-Za-z_$][\w$]*)\s*\(');

List<_Site> _scan(String file) {
  final raw = File(file).readAsStringSync();
  final rawLines = raw.split('\n');
  final lines = _blankCommentsAndStrings(raw).split('\n');
  final out = <_Site>[];
  var cls = '<top level>';
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('}')) cls = '<top level>';
    final d = _typeDecl.firstMatch(line) ??
        _recordReturnDecl.firstMatch(line) ??
        _topLevelDecl.firstMatch(line);
    if (d != null) cls = d.group(1)!;
    for (final m in [
      ..._verdictColour.allMatches(line),
      ..._verdictIcon.allMatches(line),
    ]) {
      out.add(_Site(file, cls, m.group(0)!, i + 1,
          (i < rawLines.length ? rawLines[i] : '').trim()));
    }
  }
  return out;
}

/// Literal l10n keys a file renders: `l.t('kick_goal_hits')`.
final _l10nKey = RegExp(r"\bt\(\s*'([A-Za-z0-9_]+)'");

List<String> _uiFiles() => Directory('lib/ui')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll('\\', '/'))
    .where((p) => p.endsWith('.dart'))
    .toList()
  ..sort();

void main() {
  final registered = <String, _Sig>{};
  for (final e in _entries) {
    registered[e.key] = e;
  }

  test('the scanner reads source, and reads only code', () {
    // A scanner that silently matches nothing would make every other test in
    // this file pass for ever. Two anchors, one positive and one negative.
    final all = _clinicalSurfaces.keys.expand(_scan).toList();
    expect(all.length, greaterThan(80),
        reason: 'the clinical surfaces draw far more than this — the scanner '
            'has stopped matching');
    expect(
        all.where((s) =>
            s.file.endsWith('advisor_screen.dart') &&
            s.token == 'Palette.good'),
        isNotEmpty,
        reason: 'the advisory tone colour is a known site');
    // …and the negative anchor, on a synthetic snippet rather than on a real
    // file, so this test keeps failing for its OWN reason when a screen
    // changes. Comment-stripping is load-bearing: the kick screen names
    // `Palette.good` once, in the comment that explains why the mint is gone,
    // and a scanner that could not tell those apart would report the ruling
    // itself as a violation.
    const snippet = '''
class _Fake extends StatelessWidget {
  // color: Palette.good,
  /// mint (`Ds.mint`) and `Icons.check_rounded` were here
  /* Palette.danger */
  final String s = 'Palette.amber and Icons.warning_amber_rounded';
  Widget build(BuildContext c) => const Text('x'); // Palette.watch
}
''';
    final cleaned = _blankCommentsAndStrings(snippet);
    expect(_verdictColour.hasMatch(cleaned), isFalse,
        reason: 'a colour named in a comment or a string is not a signal');
    expect(_verdictIcon.hasMatch(cleaned), isFalse,
        reason: 'an icon named in a comment or a string is not a signal');
    expect(cleaned.split('\n').length, snippet.split('\n').length,
        reason: 'blanking must preserve line numbers, or every failure message '
            'in this file points at the wrong line');
    expect(_verdictColour.hasMatch(_blankCommentsAndStrings(
        '  color: mine ? Palette.good : Ds.coralCta,')), isTrue,
        reason: 'and a colour in CODE still is one');
  });

  test('every verdict signal on a clinical screen is registered', () {
    final found = <String, List<_Site>>{};
    for (final f in _clinicalSurfaces.keys) {
      for (final s in _scan(f)) {
        found.putIfAbsent(s.key, () => []).add(s);
      }
    }

    final problems = <String>[];
    for (final entry in found.entries) {
      final sites = entry.value;
      final reg = registered[entry.key];
      if (reg == null) {
        problems.add('UNREGISTERED  ${entry.key}  ×${sites.length}\n'
            '${sites.map((s) => '      ${s.file}:${s.line}  ${s.source}').join('\n')}\n'
            "      const _Sig('${sites.first.file}', '${sites.first.cls}', "
            "'${sites.first.token}', ${sites.length},\n"
            "          claim: '', basis: ''),");
      } else if (reg.n != sites.length) {
        problems.add('COUNT CHANGED ${entry.key}: registered ${reg.n}, found '
            '${sites.length}\n'
            '${sites.map((s) => '      ${s.file}:${s.line}  ${s.source}').join('\n')}');
      }
    }

    expect(problems, isEmpty,
        reason: '\n\nA colour or an icon on a clinical screen is making a claim '
            'nobody wrote down.\n\n${problems.join('\n\n')}\n\n'
            'Register each with what a reader concludes from it (`claim`) and '
            'on what\nauthority (`basis`). If it grades her, take that sentence '
            'to the clinical gate\nfirst. `claim: \'n/a\'` is not an answer.\n');
  });

  test('the manifest does not register a signal that is no longer there', () {
    final live = <String>{};
    for (final f in _clinicalSurfaces.keys) {
      live.addAll(_scan(f).map((s) => s.key));
    }
    final stale = registered.keys.where((k) => !live.contains(k)).toList()..sort();
    expect(stale, isEmpty,
        reason: 'these registrations describe a signal that no longer exists — '
            'delete them so the manifest stays a description of the app:\n'
            '${stale.join('\n')}');
  });

  test('no site is registered twice', () {
    final seen = <String>{};
    final dupes = <String>[];
    for (final e in _entries) {
      if (!seen.add(e.key)) dupes.add(e.key);
    }
    expect(dupes, isEmpty,
        reason: 'two registrations for the same site — the second silently '
            'replaced the first:\n${dupes.join('\n')}');
  });

  test('the manifest does not register a refused signal', () {
    // Belt and braces: a registration with a reason would otherwise be a
    // perfectly ordinary way to bring one of these back.
    final wrong = <String>[];
    for (final r in _refused) {
      for (final e in _entries) {
        if (e.file == r.file &&
            e.token == r.token &&
            (r.cls == '*' || e.cls == r.cls)) {
          wrong.add(e.key);
        }
      }
    }
    expect(wrong, isEmpty,
        reason: 'a refused signal cannot be registered back in with a reason:\n'
            '${wrong.join('\n')}');
  });

  test('«pinned, unreviewed» has not grown', () {
    final pinned =
        _entries.where((e) => e.basis.startsWith('PINNED')).toList();
    expect(pinned.length, lessThanOrEqualTo(_pinnedCap),
        reason: 'PINNED means «frozen at what it already drew», not «approved». '
            'It is honest for the $_pinnedCap colours that were already live '
            'when this manifest was seeded and dishonest for one added '
            'afterwards: a new clinical colour is a decision somebody is making '
            'today. Take it to the gate and give it a basis, or lower the cap.');
  });

  test('every registration says what it asserts and on what basis', () {
    final thin = <String>[];
    for (final e in _entries) {
      if (e.claim.trim().length < 12) thin.add('${e.key}: claim too thin');
      if (e.basis.trim().length < 12) thin.add('${e.key}: basis too thin');
      if (e.claim.trim() == e.basis.trim()) {
        thin.add('${e.key}: claim and basis are the same sentence');
      }
      final c = e.claim.toLowerCase();
      for (final dodge in const ['n/a', 'none', 'tbd', 'todo', '-', '?']) {
        if (c == dodge) thin.add('${e.key}: «${e.claim}» is not an answer');
      }
    }
    expect(thin, isEmpty, reason: thin.join('\n'));
  });

  test('a refused verdict has not come back', () {
    final problems = <String>[];
    for (final r in _refused) {
      final hits = _scan(r.file)
          .where((s) => (r.cls == '*' || s.cls == r.cls) && s.token == r.token)
          .toList();
      if (hits.isNotEmpty) {
        problems.add('${r.file} :: ${r.cls} :: ${r.token}\n'
            '${hits.map((s) => '      ${s.file}:${s.line}  ${s.source}').join('\n')}\n'
            '      ${r.why}');
      }
    }
    expect(problems, isEmpty,
        reason: '\n\nA signal the clinical gate REFUSED is back on screen:\n\n'
            '${problems.join('\n\n')}\n');
  });

  test('every screen that prints clinical copy and grades in colour is classified', () {
    final unclassified = <String>[];
    for (final f in _uiFiles()) {
      if (_clinicalSurfaces.containsKey(f) || _offSurfaces.containsKey(f)) continue;
      final src = _blankCommentsAndStrings(File(f).readAsStringSync());
      final rawSrc = File(f).readAsStringSync();
      final medical = _l10nKey
          .allMatches(rawSrc)
          .map((m) => m.group(1)!)
          .where(isMedicalKey)
          .toSet();
      if (medical.isEmpty) continue;
      if (!_verdictColour.hasMatch(src) && !_verdictIcon.hasMatch(src)) continue;
      unclassified.add('$f  (renders ${medical.take(3).join(', ')}…)');
    }
    expect(unclassified, isEmpty,
        reason: '\n\nThese files print copy the clinical manifest reviews AND '
            'draw a verdict\ncolour or icon, and neither list mentions them. '
            'Put each in `_clinicalSurfaces`\nor in `_offSurfaces` with the '
            'reason it is out:\n\n${unclassified.join('\n')}\n');
  });

  test('the scope lists name files that exist, and do not overlap', () {
    final missing = [..._clinicalSurfaces.keys, ..._offSurfaces.keys]
        .where((f) => !File(f).existsSync())
        .toList();
    expect(missing, isEmpty, reason: 'renamed or deleted: ${missing.join(', ')}');
    final both =
        _clinicalSurfaces.keys.where(_offSurfaces.containsKey).toList();
    expect(both, isEmpty, reason: 'in and out at once: ${both.join(', ')}');
    for (final e in {..._clinicalSurfaces, ..._offSurfaces}.entries) {
      expect(e.value.trim().length, greaterThan(20),
          reason: '${e.key} is listed without a reason');
    }
  });
}
