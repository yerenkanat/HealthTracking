/// HealthDashboardView — the premium, reassuring health home. Top-to-bottom:
///   1. a "peace of mind" master banner that summarizes everything in one warm line
///      (green when steady, warm amber when something is worth watching),
///   2. a 2×2 grid of soft metric cards — heart rate, blood oxygen, a MERGED
///      blood-pressure card ("138 / 77 mmHg"), and temperature — each with a
///      smoothed spline chart and a distinct icon/colour,
///   3. a friendly advisor entry prompt that opens the data-driven advisor.
///
/// Pure presentation over the verified health_series + health_advisor logic.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/antenatal_protocol.dart';
import '../../domain/appointment.dart';
import '../../domain/current_advisories.dart';
import '../../domain/health_advisor.dart';
import '../../domain/health_series.dart';
import '../../domain/setup_checklist.dart';
import '../../domain/sleep.dart';
import '../../domain/child_growth.dart';
import '../../domain/cycle_insights.dart';
import '../../domain/cycle_log.dart';
import '../../domain/cycle_predictions.dart';
import '../../domain/timeline_content.dart';
import '../common/daily_audio_card.dart';
import '../content/timeline_content_card.dart';
import 'child_hero.dart';
import 'device_temp_note.dart';
import 'no_band_card.dart';
import 'cycle_hero.dart';
import 'stage_hero.dart';
import '../../domain/weekly_digest.dart';
import '../../domain/wearable_metrics.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/fitted_title.dart';
import '../widgets/glass.dart';
import 'health_summary.dart';
import 'metric_detail_screen.dart';
import 'sleep_card.dart';
import 'sparkline.dart';
import '../ds_widgets.dart';
import 'water_card.dart';

class MetricSpec {
  final String key;
  final String unit;
  final IconData icon;
    final Color color;
  const MetricSpec(this.key, this.unit, this.icon, this.color);
}

const _hrColor = Color(0xFFFF5A7A);
const _tempA = Color(0xFFF59E0B);
// (_tempB is gone: it was the second stop of the temperature gradient, and the
// design system has no gradients.)

// The three single-value metrics shown as uniform grid cards; blood pressure is
// rendered separately (two values merged into one card).
const _specs = <MetricSpec>[
  MetricSpec('hr', 'bpm', Icons.favorite_rounded,
      _hrColor),
  MetricSpec('spo2', '%', Icons.air_rounded, Palette.teal),
  MetricSpec('temp', '°C', Icons.thermostat_rounded,
      _tempA),
];

class HealthDashboardView extends StatelessWidget {
  final List<HealthSample> samples;
  final List<SleepSummary> sleepNights;
  final String greetingName;
  final String? photoPath;
  final AppLocale? currentLocale;
  final void Function(AppLocale)? onLocaleChange;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenAdvisor;

  /// Screen 39 — «Центр уведомлений», from the screen the app opens on.
  ///
  /// The bell used to exist only on the child map, so a woman who is pregnant
  /// and has added no child had NO route to it: the back office publishes a
  /// рассылка to exactly those people (admin frame 06), counts it delivered,
  /// and she could never open it. Null hides the bell.
  final VoidCallback? onOpenNotifications;

  /// How many alerts and рассылки she has not read — the badge on the bell.
  /// The same figure the map's bell carries, because it is one inbox.
  final int notificationCount;
  final String
      summaryStatus; // pregnancy/cycle status line for the shared summary
  // Quick status chip: cycle day / pregnancy week (empty = hidden).
  final String statusChip;
  final bool statusChipPregnancy;
  final bool statusChipLate; // period overdue → amber, not routine rose
  final VoidCallback? onOpenStatus;
  final WeeklyDigest? weeklyDigest; // this-week roll-up (null/no-data = hidden)
  /// Which measurement is waiting on a confirming reading — 'bp', 'fever',
  /// 'spo2', 'hr' — or null when nothing is. See emergency_confirmation.dart.
  final String? awaitingRepeat;

  final SetupProgress?
      setupProgress; // first-run checklist (null/complete = hidden)
  // Routed with the step being nudged, so each lands on the right screen.
  final void Function(SetupStep step)? onOpenSetup;
  final Appointment? nextAppointment; // soonest upcoming (null = hidden)
  final DateTime? nowForAppointment; // anchor for the countdown
  final VoidCallback? onOpenAppointments;

  /// Completed gestational week, when pregnant — drives the antenatal-protocol
  /// card ("the state plan says a visit is due now / at weeks X–Y"). Null when
  /// not pregnant, which hides the card.
  final int? pregnancyWeek;
  final VoidCallback? onOpenAntenatalPlan; // tap → the eight-visit schedule
  final VoidCallback? onLogVitals; // hand-entered reading (no band required)
  /// True when a wearable is wired but not currently delivering readings, so
  /// the numbers on screen may be stale. Shows a quiet "not measuring" chip.
  final bool bandNotMeasuring;

  /// Whether the weekly cuff calibration behind a WRIST blood pressure has
  /// expired — `bpCalibrationIsStale(controller.bpCalibration, now)`.
  ///
  /// The second condition on the blood-pressure row of the freshness table: a
  /// device BP is full colour only «≤ 4 h AND calibration ≤ 8 days», and is
  /// «not shown as current … always when calibration is stale». It has no
  /// effect on a cuff reading she typed in, which has no offset to expire.
  ///
  /// Defaults to TRUE, matching `bpCalibrationIsStale(null, …)`: never
  /// calibrated is stale, because there is nothing to trust. A default of false
  /// would hand every un-wired caller — including every test — the full-colour
  /// treatment for a reading whose calibration nobody asked about.
  final bool bpCalibrationStale;

  /// The watch's latest activity/sleep/wellness snapshot (null = none). Drives
  /// the activity panel below the vitals.
  final WearableMetrics? wearable;

  /// How many days of stored history the watch actually returned on the last
  /// backfill. Null or 0 hides the line.
  ///
  /// This is the COUNT OF DAYS WITH DATA, not the window the sync asked for.
  /// The charts below reach back as far as this and no further, and the reader
  /// cannot tell the difference by looking — so the number has to be the one
  /// the watch gave, or the label is a claim about a period nobody measured.
  final int? watchHistoryDays;
  // Hydration (optional — the card shows only when wired up).
  final int waterCount;
  final int waterGoal;

  /// Timeline content: the stage the family is at, and its lessons/products.
  /// Her pregnancy, when there is one. Drives screen 53's hero — the app's
  /// first block, because it is what she opened it for.
  final GestationInfo? gestation;

  /// Today's figures for the three quick actions. Null means «ещё нет» rather
  /// than a zero, which reads as a measurement.
  final int? kicksToday;
  final bool loggedWellbeingToday;
  final double? latestWeightKg;
  final VoidCallback? onLogKick;
  final VoidCallback? onLogDay;
  final VoidCallback? onLogWeight;

  /// Her cycle, when she is neither expecting nor a mother. Drives screen 55.
  /// Opens the vitals sheet on its camera path. Null with no server: the dark
  /// card then stays off the screen rather than offering what cannot work.
  final VoidCallback? onScanMonitor;

  /// The child screen 54's block is about — the selected one with a birth
  /// date. Null when she has no child, or none with a date to count from.
  final String? childHeroName;
  final int? childHeroAgeMonths;
  final List<GrowthPoint> childGrowth;
  final VoidCallback? onOpenChild;

  /// True once she has a child, which retires the «Есть ребёнок» router.
  final bool hasChild;

  final CycleInfo? cycleInfo;
  final CyclePhaseInfo? cyclePhase;
  final PredictionConfidence cycleConfidence;

  /// «Что дальше» — the three routers. Shown under the wellness zone so the
  /// screen does not open on a question.
  final VoidCallback? onPlanning;
  final VoidCallback? onPregnant;
  final VoidCallback? onHasChild;

  /// «Аудио дня» — screens 04 and 55 both put it on Сегодня.
  ///
  /// 'pregnancy' or 'child', with the calendar day it is keyed on (gestational
  /// day, or day of life). An operator uploads a clip every morning and it
  /// appeared only on the pregnancy calendar and the child-development screen
  /// — never on the screen the app opens on. Null on either hides it, which is
  /// the state before there is a due date or a child with a birth date.
  final String? audioTrack;
  final int? audioDay;

  final TimelineStage? timelineStage;
  final List<ContentItem> timelineItems;
  final void Function(ContentItem item)? onOpenContent;
  final VoidCallback? onSeeAllContent;
  final VoidCallback? onLogSleep;
  final VoidCallback? onAddWater;
  final VoidCallback? onRemoveWater;
  final ValueChanged<int>? onSetWaterGoal;
  final VoidCallback? onOpenWaterHistory;
  const HealthDashboardView({
    super.key,
    required this.samples,
    this.sleepNights = const [],
    this.greetingName = '',
    this.photoPath,
    this.currentLocale,
    this.onLocaleChange,
    this.onOpenProfile,
    this.onOpenAdvisor,
    this.onOpenNotifications,
    this.notificationCount = 0,
    this.summaryStatus = '',
    this.statusChip = '',
    this.statusChipPregnancy = false,
    this.statusChipLate = false,
    this.onOpenStatus,
    this.weeklyDigest,
    this.setupProgress,
    this.onOpenSetup,
    this.nextAppointment,
    this.nowForAppointment,
    this.onOpenAppointments,
    this.pregnancyWeek,
    this.onOpenAntenatalPlan,
    this.onLogVitals,
    this.bandNotMeasuring = false,
    this.bpCalibrationStale = true,
    this.wearable,
    this.watchHistoryDays,
    this.awaitingRepeat,
    this.waterCount = 0,
    this.waterGoal = 8,
    this.gestation,
    this.kicksToday,
    this.loggedWellbeingToday = false,
    this.latestWeightKg,
    this.onLogKick,
    this.onLogDay,
    this.onLogWeight,
    this.onScanMonitor,
    this.childHeroName,
    this.childHeroAgeMonths,
    this.childGrowth = const [],
    this.onOpenChild,
    this.hasChild = false,
    this.cycleInfo,
    this.cyclePhase,
    this.cycleConfidence = PredictionConfidence.low,
    this.onPlanning,
    this.onPregnant,
    this.onHasChild,
    this.audioTrack,
    this.audioDay,
    this.timelineStage,
    this.timelineItems = const [],
    this.onOpenContent,
    this.onSeeAllContent,
    this.onLogSleep,
    this.onAddWater,
    this.onRemoveWater,
    this.onSetWaterGoal,
    this.onOpenWaterHistory,
  });

  /// Whether a device is putting readings on this screen.
  ///
  /// NOT `samples.isNotEmpty`. A hand-typed reading goes into the same store as
  /// band telemetry, so "she has samples" was read as "she has a band" — and the
  /// manual-entry card, gated on the negation, disappeared the instant she used
  /// it. One typed blood pressure removed the four buttons that had taken it,
  /// the тонометр camera and the sleep entry, leaving an unlabelled app-bar
  /// icon as the only remaining route into the feature she had just started
  /// using. The provenance the store now carries is the question that was
  /// actually being asked.
  bool get _bandSupplying =>
      samples.any((s) => s.source == ReadingSource.sensor);

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // The antenatal nudge is shown only when it's actionable — a visit is due
    // this week, or a dated screening window is open. Computed here so the "Care"
    // zone can decide whether it has anything to show.
    final pregWeek = pregnancyWeek;
    final showAntenatal = pregWeek != null &&
        (visitAtWeek(pregWeek) != null || windowsOpenAt(pregWeek).isNotEmpty);
    // ONE clock for the whole screen. Every vitals surface below asks how old a
    // reading is, and two of them reading `DateTime.now()` a millisecond apart
    // is how a tile and its own banner end up disagreeing about which side of a
    // threshold the same reading is on.
    final now = nowForAppointment ?? DateTime.now();
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leadingWidth: onOpenProfile == null ? null : 60,
          leading: onOpenProfile == null
              ? null
              : _AvatarButton(
                  name: greetingName,
                  photoPath: photoPath,
                  onTap: onOpenProfile!),
          title: FittedTitle(greetingName.isEmpty
              ? l.t('db_title')
              : l.t('db_greeting', {'name': greetingName})),
          actions: [
            // Screen 39, from the screen the app opens on. First of the
            // actions, because it is the only one that can be carrying
            // something new: the рассылка the back office sent this morning.
            if (onOpenNotifications != null)
              IconButton(
                icon: Badge.count(
                  count: notificationCount,
                  isLabelVisible: notificationCount > 0,
                  backgroundColor: Palette.danger,
                  child: const Icon(Icons.notifications_none_rounded,
                      color: Palette.textDim),
                ),
                tooltip: l.t('ntf_title'),
                onPressed: onOpenNotifications,
              ),
            if (onLogVitals != null)
              IconButton(
                icon:
                    const Icon(Icons.add_chart_rounded, color: Palette.textDim),
                tooltip: l.t('vitals_log'),
                onPressed: onLogVitals,
              ),
            if (samples.isNotEmpty)
              IconButton(
                icon:
                    const Icon(Icons.ios_share_rounded, color: Palette.textDim),
                tooltip: l.t('db_share'),
                onPressed: () => _shareSummary(context, l),
              ),
            if (onLocaleChange != null)
              PopupMenuButton<AppLocale>(
                icon: const Icon(Icons.language, color: Palette.textDim),
                color: Palette.surfaceHi,
                initialValue: currentLocale,
                onSelected: onLocaleChange,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: AppLocale.ru, child: Text('Русский')),
                  PopupMenuItem(value: AppLocale.kk, child: Text('Қазақша')),
                  PopupMenuItem(value: AppLocale.en, child: Text('English')),
                ],
              ),
            const SizedBox(width: 4),
          ],
        ),
        // ONE list, in every state.
        //
        // This used to be `samples.isEmpty ? … : …`: with no band readings the
        // screen collapsed to a setup checklist and the manual-entry card, and
        // dropped the stage hero, the three quick actions, the content shelf,
        // the appointment card and everything else — for a woman who had just
        // told the app she is pregnant and given it a due date. The two things
        // are unrelated: a hero driven by a due date does not need a bracelet
        // reading. Only the blocks that literally chart samples are gated on
        // having samples; the manual diary (screen 05) takes the vitals grid's
        // place rather than the whole screen's.
        body: ListView(
                padding: EdgeInsets.fromLTRB(16, samples.isEmpty ? 12 : 4, 16, 28),
                children: [
                  if (statusChip.isNotEmpty && onOpenStatus != null) ...[
                    _StatusChip(
                        label: statusChip,
                        pregnancy: statusChipPregnancy,
                        late: statusChipLate,
                        onTap: onOpenStatus!),
                    const SizedBox(height: 12),
                  ],
                  // Setup guidance outranks ambient status: an unfinished app
                  // shouldn't hide "add a child" below a 2x2 grid of metrics.
                  // Above everything: a reading crossed an emergency threshold
                  // once and needs confirming. Not an emergency takeover — one
                  // wrist estimate does not justify that — but the most
                  // important thing on the screen until it resolves.
                  if (awaitingRepeat != null) ...[
                    _RepeatReadingCard(
                        family: awaitingRepeat!, onLog: onLogVitals),
                    const SizedBox(height: 14),
                  ],
                  if (setupProgress != null && !setupProgress!.complete) ...[
                    _SetupCard(progress: setupProgress!, onTap: onOpenSetup),
                    const SizedBox(height: 14),
                  ],
                  // Only with readings behind it: "everything is steady" said
                  // over an empty list is a reassurance nothing measured.
                  if (samples.isNotEmpty) ...[
                    _PeaceOfMindBanner(
                        samples: samples,
                        now: now,
                        bpCalibrationStale: bpCalibrationStale),
                    const SizedBox(height: 18),
                  ],

                  // «Главная зависит от этапа … Показатели браслета всегда
                  // ниже — они не главные.»
                  //
                  // This screen opened on four band readings and never
                  // mentioned that she is twenty weeks pregnant. The stage, its
                  // content and both callbacks were passed in from home_shell
                  // and dropped: four constructor parameters read by nothing.
                  // TimelineContentCard was already built and tested for
                  // exactly this and was mounted only on the calendar.
                  //
                  // With no due date and no child it explains what to add
                  // rather than drawing an empty shelf, so it is safe to lead
                  // with in every state.
                  // Screen 53's hero, when she is expecting: the week, how big
                  // the baby is, and how far along. This is what she opened the
                  // app for, so it is the first thing under the greeting.
                  if (gestation != null) ...[
                    PregnancyHero(gestation: gestation!, onTap: onOpenStatus),
                    const SizedBox(height: 12),
                    // «Три быстрых действия (Шевеления / Самочувствие / Вес)».
                    QuickActionRow(actions: [
                      QuickAction(
                        icon: Icons.child_care_rounded,
                        tint: Ds.pastelMint,
                        iconColor: Ds.mintText,
                        label: L10nScope.of(context).t('log_kicks'),
                        value: kicksToday == null
                            ? null
                            : '$kicksToday ${L10nScope.of(context).t('kick_today')}',
                        onTap: onLogKick,
                      ),
                      QuickAction(
                        icon: Icons.mood_rounded,
                        tint: Ds.pastelLilac,
                        iconColor: Ds.coralText,
                        label: L10nScope.of(context).t('qa_wellbeing'),
                        value: L10nScope.of(context)
                            .t(loggedWellbeingToday ? 'qa_logged_today' : 'qa_not_yet'),
                        onTap: onLogDay,
                      ),
                      QuickAction(
                        icon: Icons.monitor_weight_outlined,
                        tint: Ds.pastelPink,
                        iconColor: Ds.coralText,
                        label: L10nScope.of(context).t('qa_weight'),
                        value: latestWeightKg == null
                            ? L10nScope.of(context).t('qa_not_yet')
                            : '${latestWeightKg!.toStringAsFixed(1)} кг',
                        onTap: onLogWeight,
                      ),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // Screen 54: she has a child and is not expecting. Age,
                  // skills and her own growth corridor — «Есть ребёнок →
                  // возраст, навыки, перцентили».
                  if (gestation == null && childHeroName != null) ...[
                    ChildHero(
                      childName: childHeroName!,
                      ageMonths: childHeroAgeMonths ?? 0,
                      growth: childGrowth,
                      onTap: onOpenChild,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Screen 55: neither expecting nor a mother yet. The cycle
                  // leads, and «Что дальше» is how she tells the app her state
                  // changed — including «Тест положительный», which the app had
                  // no entry point for at all.
                  if (gestation == null && childHeroName == null && cycleInfo != null) ...[
                    CycleHero(
                      info: cycleInfo!,
                      phase: cyclePhase,
                      confidence: cycleConfidence,
                      onTap: onOpenStatus,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // «Аудио дня», above the shelf — spec screens 04 and 55 both
                  // place it here. Somebody in the back office records a clip
                  // for today and it was on two screens neither of which is
                  // the one the app opens on. The card renders nothing at all
                  // on a day with no clip, so it costs an empty day no space.
                  if (audioTrack != null && audioDay != null)
                    DailyAudioCard(
                      track: audioTrack!,
                      day: audioDay!,
                      margin: const EdgeInsets.only(bottom: 14),
                    ),
                  TimelineContentCard(
                    stage: timelineStage,
                    items: timelineItems,
                    onOpen: onOpenContent,
                    onSeeAll: onSeeAllContent,
                  ),
                  const SizedBox(height: 18),
                  // Screen 05, in the slot the vitals grid would occupy. This
                  // used to be a watch icon and «Наденьте браслет — и данные
                  // появятся здесь»: the band upsell the spec forbids by name,
                  // shown to a woman who has not bought one — and for most of
                  // them that is the permanent state of this app, not a step on
                  // the way to buying.
                  //
                  // «Без устройства приложение полноценно.»
                  //
                  // Gated on whether a BAND is supplying readings, not on
                  // whether any exist: typed readings land in the same store, so
                  // `samples.isEmpty` deleted this card the moment she used it.
                  // It now stays for as long as she is the person it is for, and
                  // sits ABOVE her own readings — the grid below is what she put
                  // there, and this is how she adds to it.
                  if (!_bandSupplying)
                    NoBandCard(
                      onLogVitals: onLogVitals,
                      onLogWeight: onLogWeight,
                      onLogSleep: onLogSleep,
                      onScanMonitor: onScanMonitor,
                      // The pregnancy quick actions above already carry «Вес»,
                      // wired to this same sheet.
                      showWeight: gestation == null,
                      // The card's own sentence has to stay true for her. With
                      // nothing logged it is an introduction — «приложение
                      // работает и без браслета». Once she has been typing
                      // readings, that reassurance has been answered, and
                      // repeating it daily addresses a decision she made long
                      // ago; what is true then is where those readings went.
                      hasLoggedReadings: samples.isNotEmpty,
                    ),
                  if (samples.isNotEmpty && !_bandSupplying)
                    const SizedBox(height: 18),
                  if (samples.isNotEmpty) ...[
                    // A section label so the vitals read as one named group, in
                    // parallel with the Activity & Wellness header below — the
                    // dashboard is scanned by zone, not as one undifferentiated
                    // run of cards. The not-measuring note sits under it, since
                    // it is about these readings.
                    _SectionLabel(L10nScope.of(context).t('db_vitals_section')),
                    const SizedBox(height: 6),
                    // «Свежесть данных подписана всегда («2 минуты назад»).»
                    //
                    // The four cards below showed a number and no time, so a
                    // heart rate of 118 read as "now" whether it was measured a
                    // minute ago or last night.
                    //
                    // This used to be the age of the newest SAMPLE, with the
                    // reasoning that all four cards come off it. They do not:
                    // the watch sends a frame every couple of minutes carrying
                    // `tempRaw = 0` for anything it did not measure, so a
                    // two-minute-old sample can be the newest thing on screen
                    // while the newest TEMPERATURE in it is nine hours old.
                    // Each card now states its own metric's age, and this line
                    // states the LEAST fresh of them — an aggregate may claim
                    // no more than the readings behind it, so the group line
                    // can under-state and can never over-state.
                    _VitalsFreshness(samples: samples, now: now),
                    // How far back the charts actually reach. Without it the
                    // sparklines look like "recently" and mean whatever the app
                    // happened to be awake for.
                    if ((watchHistoryDays ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          L10nScope.of(context)
                              .t('db_watch_history_span', {'n': watchHistoryDays}),
                          style: const TextStyle(
                              color: Palette.textDim, fontSize: 12, height: 1.4),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (bandNotMeasuring) ...[
                      const _NotMeasuringChip(),
                      const SizedBox(height: 12),
                    ],
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.94,
                      children: [
                        for (final spec in _specs)
                          _MetricCard(
                              spec: spec,
                              samples: samples,
                              now: now,
                              bpCalibrationStale: bpCalibrationStale),
                        _BloodPressureCard(
                            samples: samples,
                            now: now,
                            bpCalibrationStale: bpCalibrationStale),
                      ],
                    ),
                    // What the temperature card is actually showing, next to the
                    // number rather than three taps away in Settings. The app
                    // stated freshness, span and connectivity and never that
                    // these are estimates — «не медицинский прибор» on the legal
                    // screen is not a qualifier on the number.
                    //
                    // Only when the reading on that card came off a device: from
                    // a thermometer she typed in, none of this is true. The same
                    // widget rides the metric detail screen — the qualifier
                    // follows the number rather than living on one surface.
                    DeviceTempNote(samples: samples),
                  ],
                  // Sleep sits directly under the vital signs — it is one of her
                  // core health readings, not something to bury in the watch
                  // detail. Without a band it shows only when there IS a night
                  // to show: NoBandCard already carries «Сон» as one of its four
                  // manual entries, and a second log-sleep button stacked under
                  // it is the duplicate-control defect.
                  //
                  // The second clause was `samples.isNotEmpty`, and it meant
                  // "the manual card is not on screen" — which stopped being the
                  // same sentence the moment that card stopped keying off
                  // emptiness. Left alone, one typed blood pressure would have
                  // put «Сон» on the page twice, six lines apart.
                  if (latestNight(sleepNights) != null ||
                      (_bandSupplying && onLogSleep != null)) ...[
                    const SizedBox(height: 14),
                    SleepCard(nights: sleepNights, onLog: onLogSleep),
                  ],
                  // The watch's activity / wellbeing, as ONE compact summary card.
                  // The full breakdown lives on its own screen (WearableDetailScreen)
                  // — keeping the detail there is what lets this page stay a glance
                  // (safety vitals + sleep + a preview) instead of a wall of watch
                  // numbers. Shown when there's any wearable data to open into.
                  if (wearable?.hasAnything ?? false) ...[
                    const SizedBox(height: 14),
                    _WearableSummaryCard(
                      m: wearable,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => WearableDetailScreen(metrics: wearable),
                      )),
                    ),
                  ],
                  // ---- Care zone ---------------------------------------------
                  // Her next visit and — only when it's actionable — the antenatal
                  // nudge, under one label so these medical-care cards read as a
                  // category distinct from the watch-data summary above them,
                  // rather than a look-alike run of buttons. The full journey
                  // (schedule + week's material) lives on the Календарь tab.
                  if (nextAppointment != null || showAntenatal) ...[
                    const SizedBox(height: 22),
                    _SectionLabel(l.t('db_zone_care')),
                    if (nextAppointment != null) ...[
                      const SizedBox(height: 12),
                      _NextAppointmentCard(
                        appt: nextAppointment!,
                        now: nowForAppointment ?? DateTime.now(),
                        onTap: onOpenAppointments,
                      ),
                    ],
                    // A live screening window closes if missed, so that prompt is
                    // too important to bury behind a tab.
                    if (showAntenatal) ...[
                      const SizedBox(height: 12),
                      _AntenatalProtocolCard(
                          week: pregWeek, onTap: onOpenAntenatalPlan),
                    ],
                  ],
                  // ---- Tools zone --------------------------------------------
                  // Her weekly digest, the water tracker and the assistant — the
                  // things she opens and acts on, gathered under one header.
                  if ((weeklyDigest?.hasData ?? false) ||
                      onAddWater != null ||
                      onOpenAdvisor != null) ...[
                    const SizedBox(height: 22),
                    // «Что дальше» — only for the state screen 55 describes:
                    // not expecting, no children. Asking a mother of two
                    // whether she has a child is noise.
                    if (gestation == null && cycleInfo != null && !hasChild) ...[
                      WhatNextRouters(
                        onPlanning: onPlanning,
                        onPregnant: onPregnant,
                        onHasChild: onHasChild,
                      ),
                      const SizedBox(height: 18),
                    ],
                    _SectionLabel(l.t('db_zone_tools')),
                    if (weeklyDigest?.hasData ?? false) ...[
                      const SizedBox(height: 12),
                      _WeeklyDigestCard(digest: weeklyDigest!),
                    ],
                    if (onAddWater != null) ...[
                      const SizedBox(height: 12),
                      WaterCard(
                        count: waterCount,
                        goal: waterGoal,
                        onAdd: onAddWater!,
                        onRemove: onRemoveWater ?? () {},
                        onSetGoal: onSetWaterGoal ?? (_) {},
                        onOpenHistory: onOpenWaterHistory,
                      ),
                    ],
                    if (onOpenAdvisor != null) ...[
                      const SizedBox(height: 12),
                      _AdvisorEntry(onTap: onOpenAdvisor!),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _shareSummary(BuildContext context, L10n l) async {
    // The clipboard is an absorber too, and the worst-placed one: the export
    // sends advisory TITLES only, so a reassurance computed here travels out of
    // the app to a reader who cannot see the ages on the tiles. It gets the
    // same clock and the same calibration answer as the screen.
    final text = buildHealthSummary(l, samples,
        nights: sleepNights,
        name: greetingName,
        status: summaryStatus,
        now: nowForAppointment ?? DateTime.now(),
        bpCalibrationStale: bpCalibrationStale);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(l.t('db_share_copied')),
          behavior: SnackBarBehavior.floating),
    );
  }
}

/// The reassuring master component: one ambient status block that summarizes
/// every metric in a single warm line. Green ring + check when everything is
/// steady; warm amber ring + the top concern when something is worth watching.
class _PeaceOfMindBanner extends StatelessWidget {
  final List<HealthSample> samples;
  final DateTime now;
  final bool bpCalibrationStale;
  const _PeaceOfMindBanner(
      {required this.samples,
      required this.now,
      required this.bpCalibrationStale});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // currentAdvisories, not overallStatus: the advisor cannot see a timestamp,
    // so «ничего необычного» was being said over readings the app knew were
    // nine hours old. Warnings still come from every reading whatever its age;
    // only the reassurance is restricted to what is current. See
    // domain/current_advisories.dart.
    final status = currentOverallStatus(samples,
        now: now, bpCalibrationStale: bpCalibrationStale);
    final (accent, icon, ringColor) = switch (status.tone) {
      AdviceTone.positive => (
          Palette.good,
          Icons.check_rounded,
          Palette.good
        ),
      AdviceTone.watch => (
          Palette.amber,
          Icons.spa_rounded,
          Palette.amber
        ),
      // NEUTRAL, and not an hourglass for every code.
      //
      // `Palette.violet` is `Ds.coralCta` — #D6004A, a near-crimson, and more
      // alarming than this app's actual warning amber one row above. The info
      // tone is what the banner shows when the app has NOTHING to report, so it
      // was painting the calmest state in the loudest colour it owns. Dim ink
      // is the same neutral the ring itself takes when there is nothing to
      // grade, a few lines down.
      //
      // The hourglass means "coming", which is true of ADV_GATHERING and false
      // of ADV_NO_CURRENT_READINGS: nothing is on its way to a woman whose
      // band has been in a drawer since yesterday, and an icon that promises
      // arrival is the same false reassurance as a sentence that does. A dash
      // instead — the mark this screen already prints for a reading it does not
      // have. No check mark and no warning triangle: neither is true here.
      AdviceTone.info => (
          Palette.textDim,
          status.code == 'ADV_NO_CURRENT_READINGS'
              ? Icons.remove_rounded
              : Icons.hourglass_bottom_rounded,
          Palette.textDim
        ),
    };

    // Data-driven ring: fraction of metrics currently in a healthy range —
    // or NOTHING, when there is no metric this product may grade.
    var withData = 0, healthy = 0;
    // Whether she has readings AT ALL on the metrics the ring is about. Kept
    // separate from `withData`, which counts only the ones that survive the
    // provenance filters below, because the two absences need different
    // answers: readings that may not be graded get a sentence, no readings at
    // all get ADV_GATHERING in the copy beside this ring and must not get a
    // second explanation of a different absence.
    var anyReading = false;
    for (final k in metricKeys) {
      final s = statsFor(buildSeries(samples, k));
      if (s == null) continue;
      anyReading = true;
      final source = latestSourceFor(samples, k);
      // A device temperature leaves the ring entirely — it is not counted as in
      // danger, and it is NOT counted as healthy either. Passing it through as
      // "not in danger" would let a wrist estimate raise the fraction, which is
      // reassurance from the same reading the review barred from making any
      // claim (docs/CLINICAL-REVIEW-WATCH.md). Dropping it makes the ring the
      // fraction of the metrics this product may actually grade.
      if (k == 'temp' && source != ReadingSource.manual) continue;
      // A device blood pressure may turn the ring RED but never green, and the
      // asymmetry is the ruling rather than a preference (refused sentence #23
      // in docs/CLINICAL-REVIEW-WATCH.md). The product DOES escalate a device
      // BP at 140/90 — triage.dart has no source check — so a wrist estimate in
      // the danger band still has to be able to pull the fraction down. What it
      // may not do is push it up: a wrist 128/82 counted as "healthy" is the
      // reassurance removed from ADV_BP_STEADY re-entering as a number in a
      // ring, which is exactly how a narrow claim becomes a whole-body one.
      final inDanger = latestInDanger(k, s, source: source);
      if ((k == 'systolic' || k == 'diastolic') &&
          source != ReadingSource.manual &&
          !inDanger) {
        continue;
      }
      // Staleness, with the SAME asymmetry as the provenance filter above, and
      // it has to be that way round or the arithmetic reassures on its own.
      //
      // An old reading may not be counted HEALTHY: a fraction is the most
      // confident register this screen has, and «3 из 3» drawn from readings
      // taken last night is a current claim from an out-of-date basis. But an
      // old reading in the DANGER band stays in, exactly as a wrist blood
      // pressure does. Dropping it would remove it from the numerator and the
      // denominator together and push the fraction UP — a stale 165/110 beside
      // one fresh heart rate would turn 1-of-2 into a complete ring. That is a
      // reassurance arriving by arithmetic, and it is the failure the absorber
      // rule was written about.
      final at = latestAtFor(samples, k);
      final freshness = at == null
          ? MetricFreshness.stale
          : metricFreshness(k, now.difference(at),
              source: source, bpCalibrationStale: bpCalibrationStale);
      if (freshness != MetricFreshness.current && !inDanger) continue;
      withData++;
      if (!inDanger) healthy++;
    }
    // NULL, not 1.0.
    //
    // `withData == 0 ? 1.0 : …` was not a display default, it was an assertion
    // in the most confident register this screen has — a complete ring — that
    // everything checked is fine, on a day when nothing was checked. And a
    // shape cannot be qualified: it is the one reassurance in this review with
    // no sentence attached to argue with. The provenance gating above made it
    // fire MORE often, because a day of wrist blood pressure and a wrist
    // temperature now skips every metric it has.
    //
    // So the state is in the type. Null means "nothing to grade" and there is
    // no number that can be mistaken for it.
    final double? fraction = withData == 0 ? null : healthy / withData;

    // Dim ink, never the healthy colour — a grey FULL ring would still be read
    // as "all good" at a glance, so the ring is empty as well as neutral. And
    // it is not hidden: removing it removes the only place the explanation can
    // hang, and a layout that shifts between days is itself a signal she will
    // read into.
    final ringInk = fraction == null ? Palette.textDim : ringColor;

    // Said in words, not only painted — and it is the SAME string that goes
    // into the semantics label below, because `db_outside_range` was exactly a
    // claim that survived in the announcement after it had been taken out of
    // the paint.
    //
    // Only when she HAS readings and none may be graded. With nothing at all,
    // the advisory beside it is already ADV_GATHERING, and two explanations of
    // two different absences confuse both.
    //
    // This sentence now also covers the day every reading is simply too old.
    // It stays true — the app really is not grading them — and it is the only
    // wording here that has been through the gate; the ages themselves are on
    // the tiles below, which is where the reader can act on them.
    final ungraded = fraction == null && anyReading ? l.t('db_ring_ungraded') : null;

    // EVERY tone renders the advisory, including the positive one.
    //
    // The positive branch used to substitute db_peace_stable* here — a second
    // copy path that escaped the clinical review, so «Ваши показатели в
    // пределах нормы» (refused sentence #2) went on shipping on the first
    // screen she opens after the advisor itself had been fixed. Nothing here
    // may compose its own reassurance; if this banner is ever wrong the fix
    // belongs in generateAdvisories, where one sentence serves every surface.
    //
    // Her NAME is deliberately gone from the headline: attaching it to a
    // normality verdict made the verdict personal, and the verdict is what was
    // refused.
    final headline = l.t(status.code);
    final sub = l.t('${status.code}_b');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: DsShape.card,
        // A flat tint of the status accent behind the ink outline — this was a
        // gradient over a 20%-alpha border, which on cream read as no edge at
        // all. It is the screen's summary, so it carries the raised step.
        //
        // Blended against the canvas rather than left translucent: the hard
        // shadow is a solid ink rectangle drawn behind the box, so a see-through
        // fill lets it read straight through and the card turns near-black.
        color: Color.alphaBlend(accent.withValues(alpha: 0.16), Ds.cream),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        boxShadow: DsShape.hardShadow,
      ),
      child: Row(
        children: [
          // The ring carries the sentence in the SEMANTICS TREE, not only in
          // the paint beside it. A reader who cannot see the arc is the reader
          // most exposed to a ring that means one thing and announces another,
          // and `db_outside_range` is the precedent: a claim removed from the
          // colour that went on being spoken aloud.
          Semantics(
            label: ungraded,
            child: MetricRing(
              fraction: fraction,
              color: ringInk,
              size: 74,
              stroke: 8,
              center: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ringColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline,
                      style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: Palette.text)),
                  const SizedBox(height: 5),
                  Text(sub,
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 13, height: 1.35)),
                  // And in words, beside the shape it explains. An empty ring
                  // on its own is an absence, and an absence is read as
                  // whatever the reader fears or hopes.
                  if (ungraded != null) ...[
                    const SizedBox(height: 6),
                    Text(ungraded,
                        style: const TextStyle(
                            color: Palette.textDim,
                            fontSize: 12.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «, 9 ч назад» for a screen reader, or null when there is no age worth
/// stating.
///
/// Reuses `agoIfKnown`, which refuses to describe a reading from the future:
/// with a disagreeing clock there is no age, and «через 3 часа» beside a
/// medical number is worse than nothing.
String? _ageLabel(L10n l, DateTime? at, DateTime now) {
  if (at == null) return null;
  final age = now.difference(at);
  final when = l.agoIfKnown(age.isNegative ? Duration.zero : age);
  return when == null ? null : ', $when';
}

/// The age of the reading on THIS tile — «2 мин назад» under the heart rate and
/// «9 ч назад» under the temperature, on the same screen, off the same watch.
///
/// The one line of this whole change a woman actually reads. The grid used to
/// carry a single group timestamp taken from the newest SAMPLE, and the watch
/// sends a sample every couple of minutes whether or not it measured anything —
/// so the freshest thing on screen dated the stalest number on it.
///
/// Amber past the metric's own window, matching the group line's convention and
/// «Батарейка, потеря связи, пропущенный скрининг — янтарные»: something needs
/// attention and nobody is in danger. Ds.amberText, never the fill — the bright
/// amber measures 2.51:1 at this size.
class _MetricAge extends StatelessWidget {
  final DateTime? at;
  final DateTime now;
  final MetricFreshness freshness;
  const _MetricAge(
      {required this.at, required this.now, required this.freshness});

  @override
  Widget build(BuildContext context) {
    final when = _ageLabel(L10nScope.of(context), at, now);
    // No age, or none that can be described: draw nothing rather than a
    // placeholder that would read as a measurement time.
    if (when == null) return const SizedBox.shrink();
    final old = freshness != MetricFreshness.current;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        when.substring(2), // drop the ", " the semantics label wants
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: old ? Ds.amberText : Palette.textDim,
          fontSize: 11,
          height: 1.1,
          fontWeight: old ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// Green / amber / red for a metric's [MetricStatus], matching the advisor's
/// tone colours so a "watch" value reads the same on every surface — and
/// ORDINARY INK for a reading the product may not judge.
///
/// GREEN IS A CLAIM. It survives only where the grade is real: a current
/// reading, on a cited band, from a source the product may reassure from —
/// heart rate, SpO2, a MANUAL temperature, a cuff blood pressure. It is not a
/// device temperature, a device blood sugar or a device blood pressure, all of
/// which now arrive here as [MetricStatus.ungraded]; this switch used to draw
/// them in `Palette.teal` because the grade's removal collapsed them onto
/// `normal`, and the colour outlived the grade.
///
/// [Palette.text] and deliberately NOT [Palette.textDim]: dim ink is what this
/// screen uses for a STALE reading, and it would say "old" about a wrist
/// estimate two minutes fresh. Body ink is correct from both sides — it is the
/// colour the app uses when it is not judging, so it reads as neither an alarm
/// nor an all-clear.
Color _statusColor(MetricStatus s) => switch (s) {
      MetricStatus.normal => Palette.teal,
      MetricStatus.ungraded => Palette.text,
      MetricStatus.watch => Palette.watch,
      MetricStatus.danger => Palette.danger,
    };

class _MetricCard extends StatelessWidget {
  final MetricSpec spec;
  final List<HealthSample> samples;
  final DateTime now;
  final bool bpCalibrationStale;
  const _MetricCard(
      {required this.spec,
      required this.samples,
      required this.now,
      required this.bpCalibrationStale});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final label = l.metricLabel(spec.key);
    final series = downsampleMean(buildSeries(samples, spec.key), 40);
    final stats = statsFor(series);
    // buildSeries drops provenance, so the grade has to be told where the
    // newest reading came from. It changes nothing for heart rate, SpO2 or
    // blood pressure; for temperature it is the difference between drawing a
    // wrist estimate in red — and announcing it as out of range — and drawing
    // it plainly with the qualifier below the grid.
    final source = latestSourceFor(samples, spec.key);
    final status = stats == null
        ? MetricStatus.normal
        : metricStatus(spec.key, stats.latest, source: source);
    // THIS metric's age, not the newest sample's. See latestAtFor.
    final at = latestAtFor(samples, spec.key);
    final freshness = at == null
        ? MetricFreshness.stale
        : metricFreshness(spec.key, now.difference(at),
            source: source, bpCalibrationStale: bpCalibrationStale);
    // Temperature is the one row the freshness table leaves blank in both
    // "grey" columns, and the reason is that it carries no colour for a stale
    // tier to withdraw: a DEVICE reading is already ungraded by provenance, and
    // withdrawing a THERMOMETER reading's grade because it is old would gate a
    // WARNING, which the absorber rule's corollary forbids. So temperature
    // keeps the grade it has and gains only its age — which is the half of this
    // defect temperature actually has, and the example the backlog item is
    // written around.
    final gradeable =
        spec.key == 'temp' || freshness == MetricFreshness.current;
    final danger = gradeable && status == MetricStatus.danger;
    // `status.isWarning`, never `status != normal`: an UNGRADED reading is not
    // an abnormal one, and the old phrasing would have given a wrist estimate
    // the raised step and the «вне безопасного диапазона» announcement — the
    // claim its grade was removed to withdraw.
    final abnormal = gradeable && status.isWarning;
    final value = stats == null ? '—' : _fmt(spec.key, stats.latest);

    return Semantics(
      // The age goes into the announcement too. `db_outside_range` is the
      // precedent in this file for a claim that survived in the semantics tree
      // after it had been taken out of the paint; a reader who cannot see the
      // grey number is the one most exposed to a nine-hour-old reading read
      // aloud as though it were now.
      label: '$label: $value ${spec.unit}'
          '${abnormal ? l.t('db_outside_range') : ''}'
          '${_ageLabel(l, at, now) ?? ''}',
      child: DsCard(
        // The raised step now means "this one wants your attention", so only an
        // out-of-range reading gets it. Passing a colour unconditionally — which
        // is what the old soft coloured glow did — put the step on all four
        // cards at once and said nothing.
        raised: abnormal,
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MetricDetailScreen(
            metricKey: spec.key,
            unit: spec.unit,
            icon: spec.icon,
            color: spec.color,
            samples: samples,
            now: now,
            bpCalibrationStale: bpCalibrationStale,
          ),
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconBadge(spec.icon, spec.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Palette.textDim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
                if (stats != null) _trend(stats.trend),
              ],
            ),
            const Spacer(),
            // A 30px monospace reading is wider than a tile on a 360dp phone —
            // "36.6" alone measures 121px in a 125px row — so the value and its
            // unit overflowed on small screens in EVERY language. Scaling down
            // only engages when it has to, so roomier screens look unchanged.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        // Grey, not the healthy teal, once the reading is past
                        // its metric's window. A colour is a grade and a grade
                        // is a claim about now.
                        color: stats == null || !gradeable
                            ? Palette.textDim
                            : _statusColor(status),
                      )),
                  const SizedBox(width: 4),
                  Text(spec.unit,
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 12)),
                ],
              ),
            ),
            _MetricAge(at: at, now: now, freshness: freshness),
            const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: Sparkline(
                points: series,
                band: gradeable ? bandFor(spec.key, source: source) : const MetricBand(),
                color: danger ? Palette.danger : spec.color,
                inDanger: danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trend(Trend t) {
    final (icon, color) = switch (t) {
      Trend.up => (Icons.north_east, Palette.watch),
      Trend.down => (Icons.south_east, Palette.blue),
      Trend.flat => (Icons.trending_flat, Palette.textDim),
    };
    return Icon(icon, size: 16, color: color);
  }

  String _fmt(String key, double v) =>
      key == 'temp' ? v.toStringAsFixed(1) : v.round().toString();
}

/// Blood pressure, presented the way clinics do: systolic / diastolic together
/// ("138 / 77 mmHg"). Danger if EITHER value is out of range. The mini chart
/// layers the diastolic wave faintly behind the systolic one.
class _BloodPressureCard extends StatelessWidget {
  final List<HealthSample> samples;
  final DateTime now;
  final bool bpCalibrationStale;
  const _BloodPressureCard(
      {required this.samples,
      required this.now,
      required this.bpCalibrationStale});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final sysSeries = downsampleMean(buildSeries(samples, 'systolic'), 40);
    final diaSeries = downsampleMean(buildSeries(samples, 'diastolic'), 40);
    final sys = statsFor(sysSeries);
    final dia = statsFor(diaSeries);
    // buildSeries throws provenance away, so each grade has to be told where
    // its own number came from — and this card asked for neither. A fresh,
    // calibrated wrist 118/76 was therefore drawn in mint, which is refused
    // sentence #23: a device blood pressure graded green on a tile. The ring
    // further up this file has had the rule since 2026-08-14 and is the model —
    // a device BP may pull the grade DOWN and never up.
    //
    // Read per half rather than once for the pair: `latestSourceFor` answers
    // for the newest sample CARRYING that metric, and grading the diastolic
    // with the systolic's provenance would be the same defect as dating a
    // number from another reading's clock.
    final sysSource = latestSourceFor(samples, 'systolic');
    final diaSource = latestSourceFor(samples, 'diastolic');
    // Each number carries its own grade, so "138 / 77" can show the systolic in
    // amber while the diastolic stays green — the reader sees which one is off.
    final sysGrade = sys == null
        ? MetricStatus.normal
        : metricStatus('systolic', sys.latest, source: sysSource);
    final diaGrade = dia == null
        ? MetricStatus.normal
        : metricStatus('diastolic', dia.latest, source: diaSource);
    // A blood pressure is ONE reading and half of one is not a reading, so an
    // ungraded half makes the pair ungraded: nothing beside «—» may be drawn
    // teal. In practice both halves share a sample and a source and go ungraded
    // together; this covers the mixed case rather than leaving it to arrive as
    // a green systolic next to an unjudged diastolic.
    final pairUngraded = sysGrade == MetricStatus.ungraded ||
        diaGrade == MetricStatus.ungraded;
    MetricStatus half(MetricStatus s) =>
        pairUngraded && s == MetricStatus.normal ? MetricStatus.ungraded : s;
    final sysStatus = half(sysGrade);
    final diaStatus = half(diaGrade);
    // The strictest row in the freshness table, and the only one with a second
    // condition: full colour «≤ 4 h AND calibration ≤ 8 days», grey to 12 h,
    // and never current beyond that or while the calibration is stale. Four
    // hours is ACOG's repeat-reading interval; eight days is the age at which
    // the offset behind a wrist estimate stops meaning anything, which is why
    // an expired calibration alone takes the colour away at any age.
    //
    // The pair is graded as one, on the OLDER half: «118 / 76» is one reading,
    // and colouring the systolic while greying the diastolic would present half
    // a blood pressure as current.
    final sysAt = latestAtFor(samples, 'systolic');
    final diaAt = latestAtFor(samples, 'diastolic');
    final at = sysAt == null || diaAt == null
        ? (sysAt ?? diaAt)
        : (sysAt.isBefore(diaAt) ? sysAt : diaAt);
    final freshness = at == null
        ? MetricFreshness.stale
        : metricFreshness('systolic', now.difference(at),
            source: sysSource, bpCalibrationStale: bpCalibrationStale);
    final gradeable = freshness == MetricFreshness.current;
    // An ungraded half carries the pair — see [worstStatus], which ranks
    // ungraded above normal and below both warnings precisely for this line.
    final status = worstStatus([sysStatus, diaStatus]);
    final danger = gradeable && status == MetricStatus.danger;
    // `isWarning`, not `!= normal`: an ungraded pair must not be announced as
    // «вне безопасного диапазона» to a screen reader, which is the same claim
    // the mint colour was making to everyone else.
    final abnormal = gradeable && status.isWarning;
    final sysV = sys == null ? '—' : sys.latest.round().toString();
    final diaV = dia == null ? '—' : dia.latest.round().toString();

    return Semantics(
      // The unit goes through l10n here too — a screen reader would otherwise
      // announce "mmHg" in the middle of a Russian sentence.
      label: '${l.t('metric_bp')}: $sysV / $diaV ${l.t('unit_mmhg')}'
          '${abnormal ? l.t('db_outside_range') : ''}'
          '${_ageLabel(l, at, now) ?? ''}',
      child: DsCard(
        // The raised step means "this one wants your attention", exactly as it
        // does on the four tiles beside this card — which is why it cannot be
        // unconditional here. `raised: true` put the step under every blood
        // pressure the app has ever drawn, including the ungraded ones this
        // change is about, and a step under a reading the product is refusing
        // to judge is the same claim the mint colour was making.
        raised: abnormal,
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MetricDetailScreen(
            metricKey: 'systolic',
            unit: 'mmHg',
            icon: Icons.monitor_heart_rounded,
            color: Palette.violet,
            samples: samples,
            now: now,
            bpCalibrationStale: bpCalibrationStale,
          ),
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _IconBadge(Icons.monitor_heart_rounded, Palette.violet),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.t('metric_bp'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Palette.textDim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
                if (sys != null) _trendIcon(sys.trend),
              ],
            ),
            const Spacer(),
            // "118 / 76 mmHg" needs ~169px in a 125px tile on a 360dp phone, in
            // every language. Scaling down keeps the whole reading — and its
            // unit — visible instead of clipping it.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(sysV,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: sys == null || !gradeable
                            ? Palette.textDim
                            : _statusColor(sysStatus),
                      )),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3),
                    child: Text('/',
                        style: TextStyle(
                            color: Palette.textDim,
                            fontSize: 22,
                            fontWeight: FontWeight.w400)),
                  ),
                  Text(diaV,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: dia == null || !gradeable
                            ? Palette.textDim
                            : _statusColor(diaStatus),
                      )),
                  const SizedBox(width: 4),
                  Text(l.t('unit_mmhg'),
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 11)),
                ],
              ),
            ),
            _MetricAge(at: at, now: now, freshness: freshness),
            const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: Stack(
                children: [
                  if (diaSeries.length >= 2)
                    Sparkline(
                        points: diaSeries,
                        band: const MetricBand(),
                        color: Palette.blue.withValues(alpha: 0.45)),
                  Sparkline(
                    points: sysSeries,
                    // The shaded zone stays for a wrist estimate, and that is
                    // the asymmetry rather than an oversight: this band is
                    // drawn at the EMERGENCY line the product already escalates
                    // a device blood pressure on, so it is a warning, and
                    // warnings are never gated on provenance. `bandFor` ignores
                    // the source for this metric for the same reason — the ring
                    // reads `latestInDanger` through it, and a device BP that
                    // lost its band would stop being able to pull the ring
                    // down. The bands that DO disappear with provenance are
                    // temperature's and blood sugar's; both are handled inside
                    // `bandFor`.
                    band: gradeable
                        ? bandFor('systolic', source: sysSource)
                        : const MetricBand(),
                    color: danger ? Palette.danger : Palette.violet,
                    inDanger: danger,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendIcon(Trend t) {
    final (icon, color) = switch (t) {
      Trend.up => (Icons.north_east, Palette.watch),
      Trend.down => (Icons.south_east, Palette.blue),
      Trend.flat => (Icons.trending_flat, Palette.textDim),
    };
    return Icon(icon, size: 16, color: color);
  }
}

/// The friendly, conversational entry to the data-driven advisor — a rounded
/// prompt row rather than a buried tab.
class _AdvisorEntry extends StatelessWidget {
  final VoidCallback onTap;
  const _AdvisorEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Palette.violet.withValues(alpha: 0.10),
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                    color: Ds.coralCta, shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome,
                    color: Colors.white, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('db_advisor_cta'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Palette.text)),
                    const SizedBox(height: 2),
                    Text(l.t('db_advisor_sub'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Palette.textDim, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: Palette.violet.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Palette.violet, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact, tappable pill showing the current cycle day or pregnancy week,
/// opening the women's-health tab. Rose for cycle, violet for pregnancy.
/// The full wearable breakdown — activity, wellbeing and sleep — on its own
/// screen, reached from the compact summary on the health home. Moving the
/// detail here is what lets the home page stay a glanceable summary (safety
/// vitals + a preview) rather than a wall of watch numbers.
class WearableDetailScreen extends StatelessWidget {
  final WearableMetrics? metrics;
  const WearableDetailScreen({super.key, this.metrics});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('wm_title'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            // Sleep now lives on the health home under the vital signs; this
            // screen is the watch's activity + wellbeing breakdown.
            if (metrics case final m? when m.hasAnything)
              _ActivityWellnessCard(m: m),
          ],
        ),
      ),
    );
  }
}

/// The compact stand-in for the wearable detail on the health home: the module
/// name, a couple of headline figures, and a chevron into [WearableDetailScreen].
/// It replaces the full activity/wellbeing/sleep cards on the main page so that
/// page stays a summary — the detail is one tap away, not gone.
class _WearableSummaryCard extends StatelessWidget {
  final WearableMetrics? m;
  final VoidCallback onTap;
  const _WearableSummaryCard({required this.m, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final bits = <String>[];
    final w = m;
    if (w != null) {
      if (w.steps > 0) {
        bits.add(
            '${_ActivityWellnessCard._grouped(w.steps)} ${l.t('wm_steps').toLowerCase()}');
      } else if (w.kcal > 0) {
        bits.add('${w.kcal} ${l.t('wm_unit_kcal')}');
      }
      if (w.stress != null) bits.add('${l.t('wm_stress')} ${w.stress}');
    }
    final preview = bits.take(2).join(' · ');

    return DsCard(
      onTap: onTap,
      child: Row(
        children: [
          const _IconBadge(Icons.monitor_heart_rounded, Palette.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('wm_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Palette.text)),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, color: Palette.textDim)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
        ],
      ),
    );
  }
}

/// Everything the watch tracks beyond the four triage vitals, as a soft grid of
/// stat tiles. Each tile is shown only when it has a value — an unmeasured
/// stress or an untracked glucose does not leave an empty box.
class _ActivityWellnessCard extends StatelessWidget {
  final WearableMetrics m;
  const _ActivityWellnessCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // Sleep is deliberately NOT tiled here — the dedicated Sleep card, now placed
    // immediately below this one, covers it far better (weekly average, quality,
    // and the deep/light/REM/awake breakdown). A "Сон N h" tile was the same
    // figure twice. The two cards form one contiguous wellness zone.

    // Two clear categories rather than one undifferentiated grid: what she DID
    // (movement) and how her body IS (physiological wellbeing). Each metric shows
    // only when measured — an untracked glucose leaves no empty tile.
    final activity = <Widget>[
      if (m.steps > 0)
        _StatTile(
            icon: Icons.directions_walk_rounded,
            colour: Palette.teal,
            label: l.t('wm_steps'),
            value: _grouped(m.steps)),
      if (m.meters > 0)
        _StatTile(
            icon: Icons.straighten_rounded,
            colour: Palette.blue,
            label: l.t('wm_distance'),
            value: _num1(m.km),
            unit: l.t('wm_unit_km')),
      if (m.kcal > 0)
        _StatTile(
            icon: Icons.local_fire_department_rounded,
            colour: Palette.watch,
            label: l.t('wm_calories'),
            value: '${m.kcal}',
            unit: l.t('wm_unit_kcal')),
    ];
    final wellbeing = <Widget>[
      if (m.stress != null)
        _StatTile(
            icon: Icons.self_improvement_rounded,
            colour: Palette.pink,
            label: l.t('wm_stress'),
            value: '${m.stress}',
            valueColor:
                _statusColor(metricStatus('stress', m.stress!.toDouble()))),
      if (m.breathRate != null)
        _StatTile(
            icon: Icons.air_rounded,
            colour: Palette.blue,
            label: l.t('wm_breath'),
            value: '${m.breathRate}',
            unit: l.t('wm_unit_brpm'),
            valueColor: _statusColor(
                metricStatus('breathRate', m.breathRate!.toDouble()))),
      // THE BLOOD-SUGAR TILE IS GONE — the panel withdrew this metric on
      // 2026-08-13 and the app kept drawing it, which is how a withdrawal on
      // one surface turns out not to be a withdrawal at all.
      //
      // What it drew: `m.bloodSugar` (the raw integer over ten), a «ммоль/л»
      // unit label our only source never claims, and a green/amber/red grade
      // from metricStatus('glucose', …) against 3.9 / 7.8 / 11.1 — three
      // numbers that appear in no file under packages/contract. The unit label
      // is the worst of the three: it tells the reader which scale to compare
      // her doctor's figure against.
      //
      // Removed rather than de-coloured, because a bare number under «Глюкоза»
      // is still read as mmol/L by anyone who has ever seen a glucometer. See
      // docs/CLINICAL-REVIEW-WATCH.md.
    ];

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No "Activity & Wellness" title over these two groups — it just
          // repeated the group names below it ("Активность" / "Самочувствие").
          // The two labelled halves carry the module's identity on their own.
          _Group(label: l.t('wm_group_activity'), tiles: activity),
          if (activity.isNotEmpty && wellbeing.isNotEmpty)
            const SizedBox(height: 16),
          _Group(label: l.t('wm_group_wellbeing'), tiles: wellbeing),
          if (!m.worn) ...[
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.watch_off_outlined,
                  size: 14, color: Palette.textDim),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(l.t('wm_off_wrist'),
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 11.5))),
            ]),
          ],
        ],
      ),
    );
  }

  static String _num1(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  static String _grouped(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// A dashboard section label — one uppercase, tracked, dim caption used for
/// every zone header (vitals, activity & wellness, …) so the screen reads as
/// named groups in a single consistent voice.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: Palette.textDim,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6),
      );
}

/// One labelled category inside the Activity & Wellness card — a small header
/// and its tiles laid three to a row, sized to the space so a long localized
/// value never pushes a fixed-width tile off screen.
class _Group extends StatelessWidget {
  final String label;
  final List<Widget> tiles;
  const _Group({required this.label, required this.tiles});

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Palette.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 9),
        LayoutBuilder(builder: (context, c) {
          const gap = 9.0;
          final tileW = (c.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final t in tiles) SizedBox(width: tileW, child: t)],
          );
        }),
      ],
    );
  }
}

/// A single metric tile. One unified design across every metric — a neutral
/// surface with the metric's colour carried only in a small icon chip. The old
/// tiles each flooded their whole box with a different pastel, so six of them
/// read as noise; this reads as one set, and sits in the same visual family as
/// the vitals cards above (their gradient _IconBadge, tinted down a tier).
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color colour;
  final String label;
  final String value;
  final String? unit;

  /// Colours the value when the reading carries a health grade (e.g. glucose).
  /// Null for neutral metrics like steps, where a colour would imply a judgement.
  final Color? valueColor;
  const _StatTile(
      {required this.icon,
      required this.colour,
      required this.label,
      required this.value,
      this.unit,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 12),
      decoration: BoxDecoration(
        // A pastel of the metric's own accent, outlined in ink — the design
        // system's stat-grid tile. It used to be cream on a hairline, which on
        // a cream screen made the tile nearly invisible.
        color: colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Ds.ink, width: 1.5),
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(height: 10),
          // scaleDown only when it has to: a long value ("12 345", or a Kazakh
          // unit) shrinks to fit the narrow tile instead of overflowing; roomy
          // values render at full size. Same guard the vitals cards use.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    maxLines: 1,
                    style: TextStyle(
                        fontFamily: DsFont.display,
                        fontFamilyFallback: DsFont.fallback,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: valueColor ?? Ds.ink)),
                if (unit != null) ...[
                  const SizedBox(width: 3),
                  Text(unit!,
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 10.5)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A quiet amber line telling her the wearable is not delivering readings right
/// now, so the numbers below may be stale — not an error, just honesty.
/// When the vitals below were measured.
///
/// «Свежесть данных подписана всегда» — and the case that matters most is the
/// one with no readings at all, where four cards of dashes used to say nothing
/// about why. It is amber past a day: stale, and «Батарейка, потеря связи,
/// пропущенный скрининг — янтарные» is the same family of "something needs
/// attention and nobody is in danger".
///
/// It states the age of the LEAST fresh metric on the grid, not of the newest
/// sample. An aggregate may claim no more than the readings behind it, and this
/// line stands over four of them: the newest sample dated the whole group at
/// two minutes while one of the numbers under it was nine hours old. Reading
/// the oldest can only under-state, which is the safe direction — and each card
/// now carries its own age, so the specific figure is never lost.
class _VitalsFreshness extends StatelessWidget {
  final List<HealthSample> samples;
  final DateTime now;
  const _VitalsFreshness({required this.samples, required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // No empty branch: this whole section only renders when there is at least
    // one sample — a dashboard with none shows _EmptyState instead, which
    // already gives the reason and the one action. A second empty state here
    // would be unreachable code pretending to be a safety net.
    if (samples.isEmpty) return const SizedBox.shrink();
    // The oldest of the per-metric latest readings. Falls back to the newest
    // sample when nothing on the grid carries a value — a sample of only blood
    // sugar, say, which no card here draws.
    DateTime? at;
    for (final k in metricKeys) {
      final metricAt = latestAtFor(samples, k);
      if (metricAt == null) continue;
      if (at == null || metricAt.isBefore(at)) at = metricAt;
    }
    at ??= samples.map((s) => s.at).reduce((a, b) => a.isAfter(b) ? a : b);
    final age = now.difference(at);
    // A clock that disagrees returns null rather than «через 3 часа», and a
    // reading with no describable age is better left unlabelled than mislabelled.
    final when = l.agoIfKnown(age.isNegative ? Duration.zero : age);
    if (when == null) return const SizedBox.shrink();

    final stale = age.inHours >= 24;
    return Text(
      l.t('db_vitals_as_of', {'when': when}),
      style: TextStyle(
        // Ds.amberText, not Palette.amber: the bright amber is a FILL, and at
        // 12px on white it measures 2.51:1 — the accessibility sweep caught it.
        color: stale ? Ds.amberText : Palette.textDim,
        fontSize: 12,
        height: 1.4,
        fontWeight: stale ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}

class _NotMeasuringChip extends StatelessWidget {
  const _NotMeasuringChip();

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _tempA.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_searching_rounded,
              size: 17, color: _tempA),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l.t('db_not_measuring'),
                style: const TextStyle(
                    fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool pregnancy;
  final bool late;
  final VoidCallback onTap;
  const _StatusChip(
      {required this.label,
      required this.pregnancy,
      required this.onTap,
      this.late = false});

  @override
  Widget build(BuildContext context) {
    // Amber for a late period — "worth a look", never an alarm red.
    final accent = pregnancy
        ? Palette.violet
        : late
            ? Palette.amber
            : Palette.roseDeep;
    final icon = pregnancy
        ? Icons.pregnant_woman_rounded
        : late
            ? Icons.schedule_rounded
            : Icons.spa_rounded;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: accent.withValues(alpha: 0.10),
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: accent),
                const SizedBox(width: 7),
                // Flexible: «22-я неделя беременности» is the longest label
                // this chip carries and it is longer again in Kazakh, so on a
                // narrow phone the chip gave way rather than the row.
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: accent,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: accent.withValues(alpha: 0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Finish setting up" — a progress bar plus the next outstanding step, so a
/// half-configured app tells you what's missing instead of feeling empty.
/// Disappears entirely once every step is done.
/// "That reading was high — take another one."
///
/// The deliberate middle ground between saying nothing and taking over the
/// screen. It has to read as calm and actionable: she is not in an emergency,
/// and telling her she might be, on one wrist estimate, is the thing this whole
/// mechanism exists to avoid.
class _RepeatReadingCard extends StatelessWidget {
  final String family;
  final VoidCallback? onLog;
  const _RepeatReadingCard({required this.family, this.onLog});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                color: Palette.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.replay_rounded,
                  size: 20, color: Palette.amber),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l.t('repeat_title_$family'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(l.t('repeat_body'),
              style: const TextStyle(
                  fontSize: 13.5, height: 1.4, color: Palette.textDim)),
          if (onLog != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: onLog, child: Text(l.t('repeat_cta'))),
            ),
          ],
        ],
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  final SetupProgress progress;
  // Routed with the step it is nudging, so the tap lands on THAT step's screen
  // (add-a-child sheet, the map for a zone, the profile editor for a name) —
  // not a single catch-all destination.
  final void Function(SetupStep step)? onTap;
  const _SetupCard({required this.progress, this.onTap});

  static String _key(SetupStep s) => switch (s) {
        SetupStep.signIn => 'setup_signin',
        SetupStep.profileName => 'setup_name',
        SetupStep.healthMode => 'setup_health',
        SetupStep.child => 'setup_child',
        SetupStep.zone => 'setup_zone',
        SetupStep.details => 'setup_details',
        SetupStep.backup => 'setup_backup',
      };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final next = progress.next!;
    return DsCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap == null ? null : () => onTap!(next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    border:
                        Border.all(color: Ds.ink, width: DsShape.borderWidth),
                    color: Palette.violet.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.rocket_launch_rounded,
                    size: 18, color: Palette.violet),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.t('setup_title'),
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Palette.text)),
              ),
              Text('${progress.done.length}/${progress.total}',
                  style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      color: Palette.violet,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 7,
              backgroundColor: Palette.glass,
              valueColor: const AlwaysStoppedAnimation(Palette.violet),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.arrow_forward_rounded,
                size: 15, color: Palette.textDim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(l.t(_key(next)),
                  style: const TextStyle(
                      color: Palette.textDim, fontSize: 12.5, height: 1.3)),
            ),
          ]),
        ],
      ),
    );
  }
}

/// The soonest upcoming appointment with a friendly countdown ("Tomorrow",
/// "in 5 days"), tappable to open the full appointments list.
class _NextAppointmentCard extends StatelessWidget {
  final Appointment appt;
  final DateTime now;
  final VoidCallback? onTap;
  const _NextAppointmentCard(
      {required this.appt, required this.now, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    final days = daysUntil(appt, now);
    final when = appointmentWhen(days);
    final (accent, badge) = switch (when) {
      ApptWhen.today => (Palette.roseDeep, l.t('appt_today')),
      ApptWhen.tomorrow => (Palette.roseDeep, l.t('appt_tomorrow')),
      ApptWhen.soon => (Palette.violet, l.t('appt_in_days', {'n': days})),
      ApptWhen.later => (Palette.textDim, l.t('appt_in_days', {'n': days})),
    };
    final time = TimeOfDay.fromDateTime(appt.at).format(context);
    return DsCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.event_rounded, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('appt_next').toUpperCase(),
                    style: const TextStyle(
                        color: Palette.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6)),
                const SizedBox(height: 3),
                Text(appt.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Palette.text)),
                const SizedBox(height: 2),
                Text('${ml.formatMediumDate(appt.at)} · $time',
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20)),
            child: Text(badge,
                style: TextStyle(
                    color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// The state antenatal protocol's own schedule, on the home screen: which of
/// the eight standard visits is due now or coming up, its gestational-week
/// window, and — when one is open — that a dated screening window is live right
/// now. This is the "when the protocol says to see the doctor" surface, sitting
/// beside her own booked appointment. Taps into the full eight-visit plan.
class _AntenatalProtocolCard extends StatelessWidget {
  final int week;
  final VoidCallback? onTap;
  const _AntenatalProtocolCard({required this.week, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final lead = currentOrNextVisit(week);
    final dueNow = visitAtWeek(week) != null;
    final openWindows = windowsOpenAt(week);

    // Term passed → no scheduled visit; the plan screen still has the 41-week
    // talk, so keep the card and lead with the "visits complete" line.
    final line = lead == null
        ? l.t('an_term_title')
        : (dueNow
            ? l.t('an_card_due', {'n': lead.number})
            : l.t('an_card_next', {'n': lead.number}));
    final accent = dueNow ? Palette.roseDeep : Palette.violet;
    final badge =
        lead == null ? null : (dueNow ? l.t('an_due_now') : l.t('an_upcoming'));
    final window = lead == null
        ? null
        : l.t('an_weeks_range', {'from': lead.fromWeek, 'to': lead.toWeek});

    return DsCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    border:
                        Border.all(color: Ds.ink, width: DsShape.borderWidth),
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(Icons.event_note_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('an_card_title').toUpperCase(),
                        style: const TextStyle(
                            color: Palette.textDim,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6)),
                    const SizedBox(height: 3),
                    Text(line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Palette.text)),
                    if (window != null) ...[
                      const SizedBox(height: 2),
                      Text(window,
                          style: const TextStyle(
                              color: Palette.textDim, fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                      border:
                          Border.all(color: Ds.ink, width: DsShape.borderWidth),
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(badge,
                      style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
            ],
          ),
          // A dated screening window (dating scan, anomaly scan, OGTT, anti-D)
          // that is OPEN right now — the part of the protocol that closes if
          // missed, so it earns a live chip.
          if (openWindows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                color: Palette.teal.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 16, color: Palette.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l.t('an_win_open')}: ${openWindows.map((w) => l.t('an_item_${w.id}')).join(', ')}',
                      style: const TextStyle(
                          color: Palette.teal,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// This-week roll-up: days logged, water glasses (+ goal days), and average
/// sleep — a friendly weekly recap card.
class _WeeklyDigestCard extends StatelessWidget {
  final WeeklyDigest digest;
  const _WeeklyDigestCard({required this.digest});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // Through the localized formatter — hand-writing "h"/"m" here put English
    // units in a Russian sentence, the same defect found on the child screen.
    final sleepLabel =
        digest.sleepNights == 0 ? '—' : l.duration(digest.avgSleepMin);
    return DsCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    border:
                        Border.all(color: Ds.ink, width: DsShape.borderWidth),
                    color: Ds.coralCta,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.calendar_view_week_rounded,
                    size: 17, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(l.t('db_week_title'),
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Palette.text)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _DigestStat(
                  value: '${digest.daysLogged}',
                  label: l.t('db_week_logged'),
                  color: Palette.violet),
              _digestDivider(),
              _DigestStat(
                value: '${digest.waterGlasses}',
                label: l.t('db_week_water', {'n': digest.waterGoalDays}),
                color: Palette.blue,
              ),
              _digestDivider(),
              _DigestStat(
                  value: sleepLabel,
                  label: l.t('db_week_sleep'),
                  color: Palette.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _digestDivider() =>
      Container(width: 1, height: 34, color: Palette.border);
}

class _DigestStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _DigestStat(
      {required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            // One line, scaled to fit. A third of the card is narrow, and the
            // localized duration is much longer than the English it was laid
            // out against — "7h 19m" became "7 ч 19 мин" and wrapped mid-value
            // into "7 ч 19" / "МИН". Wrapping is legal layout, so nothing
            // failed; it just looked broken.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  maxLines: 1,
                  style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Palette.textDim, fontSize: 11, height: 1.2)),
          ],
        ),
      );
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge(this.icon, this.color);
  @override
  // A solid accent block with a white glyph and an ink outline. The [gradient]
  // is still in the signature because every metric spec carries one; only its
  // first stop is used, since the design system has no gradients.
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      );
}

class _AvatarButton extends StatelessWidget {
  final String name;
  final String? photoPath;
  final VoidCallback onTap;
  const _AvatarButton(
      {required this.name, required this.onTap, this.photoPath});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: PhotoAvatar(photoPath: photoPath, name: name, size: 38),
      ),
    );
  }
}
