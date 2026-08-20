/// Women's Health & Symptom Calendar (Tab 2). Three stacked zones:
///   1. a gestation header — horizontal 7-day strip + "Week 24, Day 3" progress,
///   2. an elegant month dot-matrix calendar; logged days carry a pastel dot,
///   3. a Flo-style bottom logging drawer (see [FloStyleCalendarDrawer]) that
///      slides up when a day is tapped, with big pill buttons for mood, symptoms,
///      and a fetal kick counter.
///
/// All data flows through the AppController (dayLogs, gestation, due date); this
/// screen is presentation + light month-grid math only.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HapticFeedback;
import '../../app/app_controller.dart';
import '../common/daily_audio_card.dart';
import '../../domain/birth_transition.dart';
import '../../domain/cycle_log.dart';
import '../../domain/contraction.dart';
import '../../domain/cycle_insights.dart'
    show
        cycleHistory,
        cycleRegularity,
        predictionConfidence,
        symptomsInPhase,
        PredictionConfidence;
import '../../domain/cycle_predictions.dart';
import '../../domain/child_development.dart' show ageInMonths;
import '../../domain/baby_development_content.dart' show childAgeWeeks, childAgeDays;
import '../../domain/family.dart' show ChildProfile;
import '../tracking/child_development_screen.dart' show ChildDevelopmentTimeline;
import '../../domain/kick_session.dart';
import '../../domain/postpartum.dart';
import '../../domain/pregnancy_milestones.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';
import 'contraction_timer_screen.dart';
import 'postpartum_screen.dart';
import 'pregnancy_warnings.dart';
import 'pregnancy_weight_screen.dart';
import 'hospital_bag_screen.dart';
import '../../domain/weight.dart';
import '../../domain/hospital_bag.dart';
import 'cycle_insights_screen.dart';
import 'day_log_sheet.dart';
import 'medications_screen.dart';
import '../widgets/fitted_title.dart';
import 'weight_history_screen.dart';
import 'cycle_summary.dart';
import 'weight_card.dart';
import 'logging_drawer.dart';
import '../../domain/timeline_content.dart';
import '../content/timeline_content_card.dart';
import 'pregnancy_hero.dart';
import '../ds_widgets.dart';
import 'week_detail_screen.dart';

/// Key on the single month grid.
///
/// Public so a test can assert BOTH halves of the frame-09 ordering: that the
/// grid is drawn above the card that explains it, and that there is exactly
/// ONE of it. The grid is built by a closure used from two positions (cycle
/// mode leads with it, the other modes do not), which is precisely the shape
/// that could regress into rendering two.
const String monthGridKey = 'month-grid';

class WomensHealthScreen extends StatefulWidget {
  final AppController controller;
  final DateTime Function() now;

  /// Stage-relevant content for the daily-tips shelf under the pregnancy hero.
  /// Optional so the screen still builds with no catalogue wired — it simply
  /// shows no tips, rather than an empty card. Reuses the same
  /// TimelineContentCard the dashboard uses, so tips are the published
  /// catalogue, never placeholder copy.
  final List<ContentItem> tips;
  final void Function(ContentItem item)? onOpenTip;
  final VoidCallback? onSeeAllTips;

  const WomensHealthScreen({
    super.key,
    required this.controller,
    DateTime Function()? now,
    this.tips = const [],
    this.onOpenTip,
    this.onSeeAllTips,
  }) : now = now ?? DateTime.now;

  @override
  State<WomensHealthScreen> createState() => _WomensHealthScreenState();
}

/// Which ONE calendar is on screen.
///
/// Not a choice. docs/CLAUDE-app-design.md, ЧАСТЬ 4 rule 2:
///
///   «Календарь один, вкладок сверху нет. Беременна — цикл скрыт полностью.
///    Родила — развитие вместо беременности. Цикл возвращается после первых
///    месячных. Переключение — событием в «⋯» («Тест положительный», «Я
///    родила»), не табом. Приоритет: беременность → развитие → цикл.»
///
/// This screen briefly shipped three chips across the top — Цикл · Беременность
/// · Ребёнок — which the rule forbids in terms, and for a reason: a pregnant
/// woman could tap «Цикл» and be shown ovulation predictions and a fertile
/// window for a body that is not producing them. Hiding the cycle during
/// pregnancy is the point of the rule, and a tab is a hole straight through it.
///
/// So the mode is DERIVED, and it moves when she reports an event — see
/// [_WomensHealthScreenState._openEvents].
enum CalendarMode { cycle, pregnancy, child }

class _WomensHealthScreenState extends State<WomensHealthScreen> {
  late DateTime _month; // first day of the visible month
  late DateTime _today;

  @override
  void initState() {
    super.initState();
    _today = _dayOnly(widget.now());
    _month = DateTime(_today.year, _today.month, 1);
  }

  /// The one calendar her state implies. Priority: pregnancy → development →
  /// cycle, exactly as the rule orders them.
  ///
  /// The middle rung is bounded by [AppController.isPostpartum], not by "a
  /// child exists". Those are not the same, and with no tab bar to escape
  /// through the difference is the whole rule: `_devChild(c) != null` is true
  /// forever, so a mother whose youngest is four would have been handed a
  /// development timeline and NO cycle calendar for the rest of her life.
  /// `isPostpartum` is "a birth in the last year and no period logged since"
  /// — which is «цикл возвращается после первых месячных», already computed,
  /// and already what suppresses the cycle predictions themselves.
  CalendarMode _modeFor(AppController c) {
    if (c.isPregnant) return CalendarMode.pregnancy;
    // A child with a birth date is what makes a development calendar possible;
    // without one there is no age to place her on the timeline, so falling
    // through to cycle is right rather than a hole.
    if (c.isPostpartum && _devChild(c) != null) return CalendarMode.child;
    return CalendarMode.cycle;
  }

  /// The child whose development calendar is shown — the selected one when it
  /// has a birth date, otherwise the first child that does.
  ChildProfile? _devChild(AppController c) {
    final sel = c.selectedChild;
    if (sel != null && sel.dateOfBirth != null) return sel;
    for (final ch in c.children) {
      if (ch.dateOfBirth != null) return ch;
    }
    return null;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The most recent birth still inside the postpartum window, or null. Drives
  /// whether the recovery card appears — an older child (birth long past) does
  /// not, so the card follows a birth and then quietly retires.
  DateTime? _recentBirth(AppController c) {
    DateTime? newest;
    for (final child in c.children) {
      final dob = child.dateOfBirth;
      if (dob == null) continue;
      if (!isPostpartumWindow(daysSinceBirth(dob, _today))) continue;
      if (newest == null || dob.isAfter(newest)) newest = dob;
    }
    return newest;
  }

  void _shiftMonth(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by, 1));

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = widget.controller;
    return StreamBuilder<void>(
      stream: c.changes,
      builder: (context, _) {
        final mode = _modeFor(c);
        final cycleMode = mode == CalendarMode.cycle;
        final pregMode = mode == CalendarMode.pregnancy;
        final childMode = mode == CalendarMode.child;

        // THE GRID IS BUILT ONCE AND PLACED TWICE — never rendered twice.
        //
        // Frame 09 orders the cycle calendar «шапка + Август ▾ → сетка месяца →
        // легенда → карточка "День 3 · менструация" → Отметить день». The grid
        // was the fifth thing on the screen instead of the first: below the
        // phase card, the usual-symptoms card, the fertile countdown, the
        // predictions card, weight and medications. On a screen titled
        // «Календарь», the calendar was off the bottom of the fold.
        //
        // Pregnancy and child mode keep the grid where it was, and that is
        // deliberate rather than timidity: in those modes the grid is a diary
        // index, and frames 08 and 54 lead with the week/month hero. Only the
        // CYCLE calendar is a screen whose subject is the month itself.
        Widget monthGrid() => _MonthCalendar(
              // Keyed so a test can assert there is exactly ONE grid on the
              // page and that it is drawn above the card explaining it.
              key: const ValueKey(monthGridKey),
              month: _month,
              today: _today,
              logs: c.dayLogs,
              cycle: cycleMode ? c.cycle : null,
              appointmentDays: {for (final a in c.appointments) dateKey(a.at)},
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onTapDay: _openDay,
            );
        final periodToday = c.logFor(_today).hasPeriod;
        return AuroraBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: FittedTitle(l.t('cal_screen_title')),
              actions: [
                if (pregMode)
                  IconButton(
                    icon: const Icon(Icons.timer_outlined),
                    tooltip: l.t('contr_title'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ContractionTimerScreen(
                                onSave: (count, dur, interval) =>
                                    c.logContractionSession(
                                        count, dur, interval),
                                // «История» opens ON TOP of the timer rather
                                // than popping it. She is timing contractions;
                                // taking the running clock away to show her a
                                // list is not a trade she asked for.
                                //
                                // Null while she has no past sessions, because
                                // the timer hides the action rather than
                                // offering an empty page.
                                onOpenHistory: c.contractionSessions.isEmpty
                                    ? null
                                    : () => _openFullHistory(
                                          l.t('contr_history'),
                                          [
                                            for (final s in c.contractionSessions)
                                              _ContractionHistoryRow(
                                                  record: s, now: _today)
                                          ],
                                        ),
                              )),
                    ),
                  ),
                // Safety content, always one tap from the main pregnancy view —
                // not buried inside a week's detail. Same card, shown here on
                // its own screen.
                if (pregMode)
                  IconButton(
                    icon: const Icon(Icons.health_and_safety_outlined),
                    tooltip: l.t('preg_warn_title'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const PregnancyWarningsScreen()),
                    ),
                  ),
                if (cycleMode && c.cycle.hasData)
                  IconButton(
                    icon: const Icon(Icons.ios_share_rounded),
                    tooltip: l.t('cyc_share'),
                    onPressed: () => _shareCycle(c.cycle, l),
                  ),
                if (cycleMode)
                  IconButton(
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: l.t('cyc_settings_title'),
                    onPressed: _openCycleSettings,
                  ),
                IconButton(
                  icon: const Icon(Icons.medication_outlined),
                  tooltip: l.t('med_title'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => MedicationsScreen(
                            controller: c, now: () => _today)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.insights_rounded),
                  tooltip: l.t('cyc_insights_title'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => CycleInsightsScreen(controller: c)),
                  ),
                ),
                // The «⋯» the rule names: the ONLY way the calendar changes.
                // Its contents depend on the mode, because the events that can
                // happen to her next depend on where she is.
                IconButton(
                  icon: const Icon(Icons.more_horiz_rounded),
                  tooltip: l.t('evt_menu'),
                  onPressed: () => _openEvents(mode),
                ),
                const SizedBox(width: 4),
              ],
            ),
            // One-tap period logging, in a bar rather than a floating button.
            //
            // As a FAB it sat ON the month grid: at rest — which is how this
            // screen is nearly always seen, the content being barely taller
            // than the viewport — it covered the last week of the month. A
            // floating control over whitespace is fine; one parked over the
            // dates it is about is not. In the layout it is always visible,
            // never covers anything, and is a wider target besides.
            bottomNavigationBar: cycleMode
                ? SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: FilledButton.icon(
                        onPressed: _logPeriodToday,
                        // White on roseDeep measures 3.58:1. Darkened so the
                        // most-used control on this screen is legible.
                        style: FilledButton.styleFrom(
                          backgroundColor: darkenForText(Palette.roseDeep),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: Icon(periodToday
                            ? Icons.check_rounded
                            : Icons.water_drop_rounded),
                        label: Text(
                          l.t(periodToday
                              ? 'cyc_period_logged'
                              : 'cyc_log_period'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                  )
                : null,
            body: ListView(
              // 24 at the bottom, not 90: nothing floats over the list any
              // more, so the padding no longer has to clear a button.
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                // Her recovery follows HER, not whichever calendar she happens
                // to be reading.
                //
                // It lived inside the cycle header, so the moment a newborn
                // made the development timeline the default — which is what
                // «родила — развитие вместо беременности» asks for — the one
                // thing on this screen that is about the MOTHER disappeared
                // behind a tab, on exactly the screen a woman six weeks after
                // giving birth opens most.
                if (childMode && _recentBirth(c) != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DsCard(
                      child: _RecoveryLink(
                        inDays: daysUntilCheck(daysSinceBirth(_recentBirth(c)!, _today)),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PostpartumScreen(
                              birthDate: _recentBirth(c)!,
                              today: _today,
                              controller: c),
                        )),
                      ),
                    ),
                  ),

                if (childMode) ...[
                  if (_devChild(c) case final child?) ...[
                    // Which child this is about — invisible with one child,
                    // essential with two.
                    if (c.children.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(l.t('cal_child_of', {'name': child.name}),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    // The same timeline the standalone screen shows, including
                    // its own daily audio clip — adding a second one here
                    // would put two players for the same day on one page.
                    ChildDevelopmentTimeline(
                      embedded: true,
                      ageMonths: ageInMonths(child.dateOfBirth!, _today),
                      ageWeeks: childAgeWeeks(child.dateOfBirth!, _today),
                      ageDays: childAgeDays(child.dateOfBirth!, _today),
                      childName: child.name,
                    ),
                  ] else
                    // Unreachable by construction — _modeFor only returns
                    // `child` when _devChild is non-null — and kept anyway as
                    // the fallback for if those two ever drift apart. Without
                    // it this branch would render NOTHING, which is the "empty
                    // calendar that looks broken" the card exists to avoid.
                    DsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.t('cal_child_empty_title'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15.5)),
                          const SizedBox(height: 8),
                          Text(l.t('cal_child_empty_body'),
                              style: const TextStyle(
                                  color: Palette.textDim, height: 1.4)),
                        ],
                      ),
                    ),
                ] else ...[
                if (cycleMode)
                  _CycleHeader(
                    controller: c,
                    today: _today,
                    onSetDueDate: _pickDueDate,
                    onOpenDay: _openDay,
                    // After a recent birth the recovery guide is the one thing
                    // worth doing from this screen, so it lives IN the card
                    // explaining why the calendar is quiet, rather than in a
                    // second card underneath repeating «после родов».
                    onOpenRecovery: _recentBirth(c) == null
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PostpartumScreen(
                                  birthDate: _recentBirth(c)!,
                                  today: _today,
                                  controller: c),
                            )),
                    recoveryInDays: _recentBirth(c) == null
                        ? null
                        : daysUntilCheck(daysSinceBirth(_recentBirth(c)!, _today)),
                  )
                else
                  _GestationHeader(
                      controller: c, today: _today, onSetDueDate: _pickDueDate),

                // Daily audio for this exact day of the calendar, right under the
                // week/day header. Renders nothing (and adds no gap) when the day
                // has no clip.
                if (pregMode && c.gestation != null)
                  DailyAudioCard(
                      track: 'pregnancy',
                      day: c.gestation!.totalDays,
                      margin: const EdgeInsets.only(top: 14)),

                // Daily tips, right under the pregnancy hero — the same
                // published catalogue the dashboard shows, keyed to her week.
                // Only in pregnancy mode: the cycle calendar has its own
                // content elsewhere, and showing an empty shelf on it would be
                // clutter. Hidden entirely when nothing is wired.
                if (pregMode && c.isPregnant && widget.onOpenTip != null) ...[
                  const SizedBox(height: 14),
                  TimelineContentCard(
                    stage: c.gestation == null
                        ? null
                        : TimelineStage.pregnancyWeek(c.gestation!.week),
                    items: widget.tips,
                    onOpen: widget.onOpenTip,
                    onSeeAll: widget.onSeeAllTips,
                  ),
                ],
                // Frame 09, in its order: the month, then what explains it.
                if (cycleMode) ...[
                  const SizedBox(height: 16),
                  monthGrid(),
                  const SizedBox(height: 14),
                  if (c.cycle.hasData)
                    const _CycleLegend()
                  // Nothing to colour in yet. The grid is thirty grey numbers
                  // with no legend under it because there is nothing to
                  // explain — so it reads as broken rather than as empty, and
                  // nothing says that tapping a day is how anything gets in.
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.touch_app_outlined,
                            size: 17, color: Palette.textDim),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(l.t('cal_grid_empty'),
                              style: const TextStyle(
                                  color: Palette.textDim,
                                  fontSize: 12.5,
                                  height: 1.45)),
                        ),
                      ],
                    ),
                ],
                if (cycleMode && c.cycle.hasData) ...[
                  const SizedBox(height: 14),
                  _CyclePhaseCard(info: c.cycle),
                  if (cyclePhaseFor(c.cycle) case final ph?)
                    Builder(builder: (_) {
                      final usual = symptomsInPhase(
                          c.dayLogs.values, c.periodDays, ph.phase);
                      if (usual.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _UsualSymptomsCard(symptoms: usual),
                      );
                    }),
                  if (fertileCountdown(c.cycle)?.state ==
                      FertileWindowState.upcoming) ...[
                    const SizedBox(height: 14),
                    _FertileCountdownCard(
                        countdown: fertileCountdown(c.cycle)!),
                  ],
                  const SizedBox(height: 14),
                  Builder(builder: (_) {
                    final reg = cycleRegularity(cycleHistory(c.periodDays));
                    return _CyclePredictions(
                      info: c.cycle,
                      confidence: predictionConfidence(
                        completedCycles: reg.cyclesConsidered,
                        variationDays: reg.variationDays,
                      ),
                      // Null means she never touched the slider, so the 28 the
                      // dates roll on is ours and the card must not call it
                      // «ваша настройка».
                      baselineChosen: c.cycleBaselineDays != null,
                    );
                  }),
                ],
                if (pregMode && c.gestation != null) ...[
                  // The baby-size + weekly highlight live on the "Подробнее" week
                  // detail page, so they're not repeated here.
                  const SizedBox(height: 14),
                  _PregnancyMilestones(week: c.gestation!.week),
                  // Third trimester: the hospital bag becomes worth packing.
                  if (c.gestation!.week >= hospitalBagFromWeek) ...[
                    const SizedBox(height: 14),
                    _HospitalBagCard(
                      checked: c.hospitalBagChecked,
                      onOpen: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => StreamBuilder<void>(
                          stream: c.changes,
                          builder: (_, __) => HospitalBagScreen(
                            checked: c.hospitalBagChecked,
                            onToggle: c.toggleHospitalBagItem,
                          ),
                        ),
                      )),
                    ),
                  ],
                ],
                if (pregMode) ...[
                  const SizedBox(height: 14),
                  WeightCard(
                    entries: c.weights,
                    onLog: (kg) => c.logWeight(_today, kg),
                    goalKg: c.weightGoalKg,
                    onSetGoal: c.setWeightGoal,
                    onOpenHistory: c.weights.isEmpty
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => WeightHistoryScreen(
                                  entries: c.weights,
                                  onDelete: c.removeWeightEntry),
                            )),
                    // Pregnancy only: how much is healthy to gain, and how her
                    // logged pace compares.
                    onOpenGuide: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PregnancyWeightScreen(
                          weeklyRateKg: weeklyGainRate(c.weights)),
                    )),
                  ),
                ],
                if (c.medications.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  MedicationCard(
                    controller: c,
                    today: _today,
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          MedicationsScreen(controller: c, now: () => _today),
                    )),
                  ),
                ],
                // Pregnancy and child mode only — the cycle calendar draws its
                // grid at the TOP (frame 09). One grid per screen either way:
                // two _MonthCalendars on one page would be two sets of day
                // targets opening the same sheet.
                if (!cycleMode) ...[
                  const SizedBox(height: 16),
                  monthGrid(),
                ],
                if (pregMode && c.kickSessions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _KickHistory(
                      sessions: c.kickSessions,
                      today: _today,
                      onClear: () => _clearHistory(
                          title: l.t('kick_history_clear_title'),
                          onConfirmed: c.clearKickSessions),
                      onOpenAll: () => _openFullHistory(l.t('kick_history'), [
                            for (final s in c.kickSessions)
                              _KickHistoryRow(record: s, now: _today)
                          ])),
                ],
                if (pregMode && c.contractionSessions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ContractionHistory(
                      sessions: c.contractionSessions,
                      today: _today,
                      onClear: () => _clearHistory(
                          title: l.t('contr_history_clear_title'),
                          onConfirmed: c.clearContractionSessions),
                      onOpenAll: () => _openFullHistory(l.t('contr_history'), [
                            for (final s in c.contractionSessions)
                              _ContractionHistoryRow(record: s, now: _today)
                          ])),
                ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _openFullHistory(String title, List<Widget> rows) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SessionHistoryScreen(title: title, rows: rows),
    ));
  }

  Future<void> _clearHistory(
      {required String title, required VoidCallback onConfirmed}) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: title,
      message: l.t('hist_clear_body'),
      confirmLabel: l.t('hist_clear'),
    );
    if (ok) onConfirmed();
  }

  Future<void> _shareCycle(CycleInfo info, L10n l) async {
    final ml = MaterialLocalizations.of(context);
    final text = buildCycleSummary(l, info,
        formatDate: ml.formatMediumDate,
        baselineChosen: widget.controller.cycleBaselineDays != null);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(l.t('cyc_share_copied')),
          behavior: SnackBarBehavior.floating),
    );
  }

  void _openCycleSettings() {
    final c = widget.controller;
    var cycleLen = c.avgCycleLength.toDouble();
    var periodLen = c.avgPeriodLength.toDouble();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) {
        final l = L10nScope.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: Palette.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(l.t('cyc_settings_title'),
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(l.t('cyc_settings_hint'),
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                const SizedBox(height: 18),
                _SliderRow(
                  label: l.t('cyc_avg_cycle_label'),
                  value: cycleLen,
                  min: 21,
                  max: 35,
                  display: l.t('cyc_days_short', {'n': cycleLen.round()}),
                  onChanged: (v) => setSheet(() => cycleLen = v),
                ),
                const SizedBox(height: 12),
                _SliderRow(
                  label: l.t('cyc_avg_period_label'),
                  value: periodLen,
                  min: 2,
                  max: 8,
                  display: l.t('cyc_days_short', {'n': periodLen.round()}),
                  onChanged: (v) => setSheet(() => periodLen = v),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.notifications_outlined,
                        size: 18, color: Palette.textDim),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.t('rem_manage_hint'),
                          style: const TextStyle(
                              color: Palette.textDim,
                              fontSize: 12.5,
                              height: 1.3)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    c.setCycleBaseline(
                        cycle: cycleLen.round(), period: periodLen.round());
                    Navigator.pop(ctx);
                  },
                  child: Text(l.t('act_save')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One tap marks today as a period day; if already logged, open the day sheet
  /// to change intensity or clear it.
  void _logPeriodToday() {
    final c = widget.controller;
    final l = L10nScope.of(context);
    if (c.logFor(_today).hasPeriod) {
      _openDay(_today);
      return;
    }
    c.toggleFlowFor(_today, Flow.medium);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l.t('cyc_period_logged_toast')),
      action: SnackBarAction(
          label: l.t('act_remove'),
          onPressed: () => c.toggleFlowFor(_today, Flow.medium)),
    ));
  }

  Future<void> _pickDueDate() async {
    final c = widget.controller;
    final initial = c.dueDate ??
        _today.add(const Duration(
            days: 140)); // elapsed-ok: a picker default, adjustable by hand
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _today.subtract(
          const Duration(days: 300)), // elapsed-ok: a generous picker bound
      lastDate: _today.add(
          const Duration(days: 300)), // elapsed-ok: a generous picker bound
      helpText: L10nScope.of(context).t('cal_due_pick'),
    );
    if (picked != null) c.setDueDate(picked);
  }

  void _openDay(DateTime day) =>
      showDayLogSheet(context, widget.controller, day);

  // ---- «⋯» — the events that move the calendar --------------------------
  //
  // docs/CLAUDE-app-design.md, ЧАСТЬ 4 rule 2: «Переключение — событием в «⋯»
  // («Тест положительный», «Я родила»), не табом.» The calendar never asks her
  // to pick a mode; it asks what happened, and derives the rest.
  //
  // Which events are offered depends on where she is, because the events that
  // can happen next do:
  //
  //   cycle       → «Тест положительный»
  //   pregnancy   → «Я родила» (the born/ended fork)
  //   development → «Тест положительный», «Месячные вернулись»
  //
  // The third one is not decoration. «Цикл возвращается после первых месячных»
  // has to be sayable, and in development mode there is no month grid and no
  // «Отметить месячные» bar to say it with — so without this entry the rule
  // would be unimplementable and a mother would sit in the development calendar
  // until the child's first birthday. Here it is one tap, and undoable.
  Future<void> _openEvents(CalendarMode mode) async {
    final l = L10nScope.of(context);
    final entries = <(String, IconData, Future<void> Function())>[
      if (mode != CalendarMode.pregnancy)
        ('evt_test_positive', Icons.pregnant_woman_rounded, _pickDueDate),
      if (mode == CalendarMode.pregnancy)
        ('evt_gave_birth', Icons.child_friendly_rounded, _endPregnancy),
      if (mode == CalendarMode.child)
        ('evt_period_back', Icons.water_drop_rounded, _periodReturned),
    ];
    final chosen = await showModalBottomSheet<Future<void> Function()>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        // Scrollable, because a bottom sheet is laid out against a height it
        // does not choose — 9/16 of the screen by default — and these rows are
        // full sentences that WRAP. At 320dp in Kazakh, with two events on the
        // menu, the column ran 18px past the sheet and Flutter painted the
        // striped bar over the second event. Nothing here is padded down or
        // capped to one line to make it fit: the labels stay whole and the
        // sheet scrolls if they need the room.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 18),
              Text(l.t('evt_title'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(l.t('evt_hint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5, height: 1.35)),
              ),
              const SizedBox(height: 10),
              for (final (key, icon, action) in entries)
                ListTile(
                  leading: Icon(icon, color: Palette.rose),
                  title: Text(l.t(key),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(l.t('${key}_sub'),
                      style: const TextStyle(fontSize: 12.5, height: 1.35)),
                  onTap: () => Navigator.pop(ctx, action),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await chosen();
  }

  /// End-of-pregnancy fork.
  ///
  /// This used to be one yes/no dialog that cleared the due date. Two entirely
  /// different events came through it: a birth, and a loss.
  ///
  /// For the birth it threw away the date the whole second half of the app is
  /// keyed on — the development calendar, the vaccinations, the growth chart —
  /// leaving a woman to add a child by hand and retype it days after giving
  /// birth. For a loss, the same door has to say nothing cheerful at all.
  ///
  /// The app CANNOT tell those two apart from data, and must not guess: it asks
  /// once, plainly, and asks nothing further. `PregnancyOutcome.ended` is
  /// deliberately one value and not a taxonomy of endings — see
  /// domain/birth_transition.dart. The design doc does not address loss at all;
  /// this fork is the app's own, and stays as reviewed.
  Future<void> _endPregnancy() async {
    final l = L10nScope.of(context);
    final c = widget.controller;
    final outcome = await showModalBottomSheet<PregnancyOutcome>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        // Scrollable for the same reason as the events menu above: two wrapping
        // subtitles in a sheet whose height is 9/16 of a 320dp phone. The one
        // sheet in the app a woman may be reading through tears is not one to
        // paint an overflow bar across.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 18),
              Text(l.t('birth_which'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.child_friendly_rounded,
                    color: Palette.rose),
                title: Text(l.t('birth_born'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(l.t('birth_born_sub'),
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
                onTap: () => Navigator.pop(ctx, PregnancyOutcome.born),
              ),
              // Deliberately plain. No icon that celebrates, no colour, no
              // follow-up — for the woman taking this path the kindest thing
              // the app can do is get out of the way.
              ListTile(
                title: Text(l.t('birth_other'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(l.t('birth_other_sub'),
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
                onTap: () => Navigator.pop(ctx, PregnancyOutcome.ended),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (!mounted || outcome == null) return;

    if (outcome == PregnancyOutcome.ended) {
      // A tap here erases the whole pregnancy calendar, and until now it did so
      // the instant it was touched — no confirmation, nothing to undo. So it
      // asks, in words that name exactly what changes and what is kept, and
      // then leaves an undo behind anyway.
      //
      // Neutral, not danger-red: «Красный только SOS», and this is the door a
      // woman uses after a loss.
      final ok = await confirmChange(
        context,
        title: l.t('cyc_end_pregnancy'),
        message: l.t('cyc_end_pregnancy_body'),
        confirmLabel: l.t('evt_tracking_off'),
      );
      if (!ok || !mounted) return;
      final previous = c.dueDate;
      c.setDueDate(null);
      _undoBar(l.t('evt_preg_off_done'), () => c.setDueDate(previous));
      return;
    }
    await _recordBirth();
  }

  /// Collect the birth date (and a name, if she has one yet) and create the
  /// child record the calendars need.
  Future<void> _recordBirth() async {
    final l = L10nScope.of(context);
    final c = widget.controller;
    final initial = defaultBirthDate(dueDate: c.dueDate, today: _today);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      // A birth cannot be in the future, and 300 days back covers any
      // pregnancy the app was tracking.
      firstDate: addDays(_today, -300),
      lastDate: _today,
      helpText: l.t('birth_date'),
    );
    if (!mounted || date == null) return;

    // The dialog owns its controller. Creating one here and disposing it after
    // showDialog returns crashes: the route's exit animation is still running
    // and the TextField still holds the controller, so the next frame uses a
    // disposed object.
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _BirthNameDialog(
        title: l.t('birth_title'),
        label: l.t('birth_name'),
        save: l.t('birth_save'),
      ),
    );
    if (!mounted || name == null) return;

    final previousDue = c.dueDate;
    final t = birthTransition(
      childId: 'child-${_today.microsecondsSinceEpoch}',
      name: name,
      birthDate: date,
      today: _today,
    );
    c.addChild(t.child!);
    c.setDueDate(null);
    if (!mounted) return;
    // Undo puts BOTH halves back — the child record this created and the due
    // date it cleared. Restoring one without the other would leave her looking
    // at a pregnancy calendar with a phantom newborn in the family list.
    _undoBar(l.t('birth_done'), () {
      c.removeChild(t.child!.id);
      c.setDueDate(previousDue);
    });
  }

  /// «Месячные вернулись» — the event that ends the postpartum pause and brings
  /// the cycle calendar back, by logging today as a period day. That is not a
  /// flag of its own: [AppController.isPostpartum] is defined as "no period
  /// logged since the birth", so the period IS the state.
  Future<void> _periodReturned() async {
    final l = L10nScope.of(context);
    final c = widget.controller;
    if (c.logFor(_today).hasPeriod) {
      _openDay(_today);
      return;
    }
    c.toggleFlowFor(_today, Flow.medium);
    _undoBar(l.t('evt_period_back_done'),
        () => c.toggleFlowFor(_today, Flow.medium));
  }

  /// A snackbar that can put the event back.
  ///
  /// Every event on this menu is a claim about her body, and every one of them
  /// changes which calendar she is looking at. A mis-tap must not be the end of
  /// it, and a confirmation dialog alone is not enough — she can confirm the
  /// wrong thing just as easily as she can tap it. So each event leaves a
  /// reversal behind that restores exactly what it changed.
  void _undoBar(String message, VoidCallback undo) {
    final l = L10nScope.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: l.t('act_undo'), onPressed: undo),
      ));
  }
}

/// Gestation header: a "Week N, Day D" progress card + a 7-day horizontal strip
/// centred on today. When no due date is set, invites the mother to add one.
class _GestationHeader extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  final VoidCallback onSetDueDate;
  const _GestationHeader(
      {required this.controller,
      required this.today,
      required this.onSetDueDate});

  /// Open the week browser. [week] null starts on her real week (the "More"
  /// button); the hero's chevrons pass the adjacent week to land there directly.
  void _openWeek(BuildContext context, GestationInfo g, int? week) {
    final l = L10nScope.of(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WeekDetailScreen(
        gestation: g,
        dueDate: controller.dueDate,
        initialWeek: week,
        onBookAntenatal: (visit, at) => controller.addAppointment(
            l.t('an_book_title', {'n': visit.number}), at),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final g = controller.gestation;

    if (g == null) {
      return DsCard(
        onTap: onSetDueDate,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                  color: Ds.coralCta, shape: BoxShape.circle),
              child: const Icon(Icons.calendar_month_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('cal_no_due_title'),
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(l.t('cal_no_due_body'),
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Palette.textDim),
          ],
        ),
      );
    }

    // The illustrated hero replaces the ring-and-text row this used to be.
    // Same three facts — how far along, which trimester, how long left — with
    // room to look at rather than a metric tile. The actions it carried are
    // kept below it, not lost.
    return Column(
      children: [
        PregnancyHero(
          gestation: g,
          weekLabel: l.t('gest_week', {'w': g.week, 'd': g.dayOfWeek}),
          trimesterLabel: l.t('gest_trimester', {'n': g.trimester}),
          remainingLabel: g.daysUntilDue >= 0
              ? l.t('gest_days_left', {'n': g.daysUntilDue})
              : l.t('gest_overdue'),
          detailsLabel: l.t('gest_details'),
          onDetails: () => _openWeek(context, g, null),
          // Prev/next chevrons on the hero open the week browser directly on the
          // adjacent week — "last / next week" without hunting for it.
          onOpenWeek: (week) => _openWeek(context, g, week),
        ),
        const SizedBox(height: 12),
        // The due date, editable. Its old neighbour — an underlined «Больше не
        // беременны?» — has moved into the «⋯» menu, where the rule puts every
        // change of calendar. Two ways to end a pregnancy, one of them a bare
        // underlined line sitting a thumb's width from the date field, was one
        // too many.
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: onSetDueDate,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.edit_calendar_outlined,
                  size: 15, color: Palette.violet),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  controller.dueDate != null
                      ? l.t('gest_due', {
                          'date': MaterialLocalizations.of(context)
                              .formatMediumDate(controller.dueDate!)
                        })
                      : l.t('cal_no_due_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Palette.violetText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _WeekStrip(
            today: today,
            logs: controller.dayLogs,
            dueDate: controller.dueDate),
      ],
    );
  }

}

/// Cycle header (non-pregnant mode): cycle day + days-to-next-period + phase,
/// with a 7-day strip. Invites the user to log a period when there's no data yet.
class _CycleHeader extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  final VoidCallback onSetDueDate;

  /// Open the recovery guide, when there is a recent birth to recover from.
  ///
  /// Inside this card rather than in one below it. Postpartum the screen
  /// opened with two stacked cards, «Цикл на паузе после родов» and
  /// «Восстановление после родов», saying "после родов" twice in a row before
  /// she reached anything she could act on. They are one subject: why the
  /// calendar is quiet, and where to read about it. This mirrors what the card
  /// already does for the not-postpartum case with _ExpectingLink.
  final VoidCallback? onOpenRecovery;
  final int? recoveryInDays;

  /// Open the day sheet on one specific date.
  ///
  /// Only used by the future-mark state below, and it is the one place in the
  /// app that reaches a FUTURE day's sheet: the month grid refuses to open one
  /// (_buildCell, `onTap: isFuture ? null`). That guard is right for browsing and
  /// wrong here — a period entry dated in the future is precisely the thing she
  /// cannot otherwise get back to and undo.
  final void Function(DateTime day)? onOpenDay;

  const _CycleHeader(
      {required this.controller,
      required this.today,
      required this.onSetDueDate,
      this.onOpenRecovery,
      this.recoveryInDays,
      this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final info = controller.cycle;

    if (!info.hasData) {
      // Postpartum the cycle is paused, not un-started: say so, and don't prompt
      // "log a period" or "expecting a baby?" to someone who just gave birth.
      final postpartum = controller.isPostpartum;
      return DsCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Palette.rose,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                      postpartum ? Icons.spa_rounded : Icons.water_drop_rounded,
                      color: Colors.white,
                      size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          l.t(postpartum
                              ? 'cyc_pp_paused_title'
                              : 'cyc_no_data_title'),
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                          l.t(postpartum
                              ? 'cyc_pp_paused_body'
                              : 'cyc_no_data_body'),
                          style: const TextStyle(
                              color: Palette.textDim,
                              fontSize: 12.5,
                              height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
            if (!postpartum) ...[
              const SizedBox(height: 6),
              _ExpectingLink(onTap: onSetDueDate),
            ] else if (onOpenRecovery != null) ...[
              const SizedBox(height: 10),
              _RecoveryLink(onTap: onOpenRecovery!, inDays: recoveryInDays),
            ],
          ],
        ),
      );
    }

    // THE DAY, OR THE ABSENCE OF ONE.
    //
    // This was `info.cycleDay ?? 1` in both the arc and the numeral, so a null
    // day drew a rose tick at twelve o'clock and printed «1» in the middle of
    // the ring: «you are on day 1 of your cycle» — the first day of bleeding, a
    // specific claim about her body produced by a fallback operator.
    //
    // Null here has exactly ONE cause and it is knowable, so the screen names
    // it rather than blanking. `computeCycle` returns a null day only when today
    // precedes [CycleInfo.lastPeriodStart] (cycle_predictions.dart:158) — a
    // period marked on a date that has not arrived. That reaches this screen
    // without her ever tapping a future day: `mergeRemoteDayLogs` replays
    // whatever another install or a restored hand-editable backup sent up, a
    // phone whose clock ran ahead writes tomorrow's key as today, and flying
    // west across the date line moves the local calendar backwards.
    final day = info.cycleDay;
    final futureMark = day == null ? info.lastPeriodStart : null;

    final loggedToday = controller.logFor(today).hasPeriod;
    final phaseType = cycleDayType(today, info, loggedPeriod: loggedToday);
    final until = info.daysUntilNextPeriod ?? 0;
    final subtitle = until > 0
        ? l.t('cyc_period_in', {'n': until})
        : until == 0
            ? l.t('cyc_period_today')
            : l.t('cyc_period_late', {'n': -until});

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Palette.rose.withValues(alpha: 0.14),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The ring carries its sentence in the SEMANTICS TREE, because a
              // dashed circle and an em dash announce nothing on their own.
              // Same treatment as the peace ring on the home screen.
              Semantics(
                // container: true, because Semantics defaults to ANNOTATING the
                // child's node and MetricRing publishes none of its own once
                // excludeSemantics has dropped the dash and the caption. The
                // label was silently going nowhere.
                container: true,
                label: day == null
                    ? l.t('cyc_day_unknown')
                    : l.t('cyc_day_n', {'n': day}),
                excludeSemantics: true,
                child: MetricRing(
                  // No day → NO ARC, and the whole circle in the not-assessed
                  // dashes (`assessed: 0`). Deliberately the vocabulary the peace
                  // ring already established rather than a second one: dashes
                  // because a solid rose arc of ANY length is a position in the
                  // cycle, and this state is the absence of a position.
                  fraction: day == null ? null : day / info.avgCycleLength,
                  assessed: day == null ? 0 : null,
                  color: Palette.rose,
                  size: 72,
                  stroke: 8,
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The dash is this product's glyph for «no reading» — the
                      // vitals tiles print it where a number would go. Body ink
                      // and not dim: dim is how STALE renders, and «not known»
                      // is a different claim from «old» (c316c29).
                      Text(day == null ? '—' : '$day',
                          style: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              height: 1)),
                      Text(l.t('cyc_day_short'),
                          style: const TextStyle(
                              color: Palette.textDim, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: futureMark != null
                    // Beside the ring, only the fact — a restatement of her own
                    // entry, no verdict on it. The explanation and the way to
                    // change it run full width below, where Kazakh has room.
                    ? Text(
                        l.t('cyc_future_mark_title',
                            {'d': humanDayMonth(futureMark, today)}),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subtitle,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          if (_phaseLabel(l, phaseType) != null)
                            _PhasePill(
                                label: _phaseLabel(l, phaseType)!,
                                type: phaseType),
                          const SizedBox(height: 6),
                          _ExpectingLink(onTap: onSetDueDate),
                        ],
                      ),
              ),
            ],
          ),
          if (futureMark != null) ...[
            const SizedBox(height: 10),
            Text(l.t('cyc_future_mark_body'),
                style: const TextStyle(
                    color: Palette.textDim, fontSize: 12.5, height: 1.3)),
            if (onOpenDay != null) ...[
              const SizedBox(height: 8),
              _FixMarkLink(onTap: () => onOpenDay!(futureMark)),
            ],
          ],
          const SizedBox(height: 16),
          _WeekStrip(today: today, logs: controller.dayLogs),
        ],
      ),
    );
  }

  String? _phaseLabel(dynamic l, CycleDayType t) => switch (t) {
        CycleDayType.period => l.t('cyc_phase_period'),
        CycleDayType.fertile => l.t('cyc_phase_fertile'),
        CycleDayType.ovulation => l.t('cyc_phase_ovulation'),
        _ => null,
      };
}

class _PhasePill extends StatelessWidget {
  final String label;
  final CycleDayType type;
  const _PhasePill({required this.label, required this.type});
  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      CycleDayType.period => Palette.roseDeep,
      CycleDayType.ovulation => Palette.teal,
      CycleDayType.fertile => Palette.teal,
      _ => Palette.textDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// The way into the recovery guide, from inside the cycle-paused card.
///
/// Same shape as [_ExpectingLink], because it plays the same role: the one
/// thing worth doing next from a header that is otherwise explaining why there
/// is nothing to show.
class _RecoveryLink extends StatelessWidget {
  final VoidCallback onTap;

  /// Days until the postpartum check-up, when that is still ahead. Null just
  /// drops the clause rather than inventing a date.
  final int? inDays;
  const _RecoveryLink({required this.onTap, this.inDays});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final days = inDays;
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.spa_outlined, size: 15, color: Palette.violet),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            days == null
                ? l.t('pp_card_title')
                : '${l.t('pp_card_title')} · ${l.t('pp_check_in', {'n': days})}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Palette.violetText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
        ),
        const Icon(Icons.chevron_right_rounded, size: 16, color: Palette.violetText),
      ]),
    );
  }
}

/// «Изменить отметку» — the way back to a period entry dated in the future.
///
/// Shaped like [_ExpectingLink] because it plays the same role: the one thing
/// worth doing from a card that is otherwise explaining why there is no number.
/// Not destructive itself — it opens that day's sheet, where clearing the flow
/// carries its own confirmation.
class _FixMarkLink extends StatelessWidget {
  final VoidCallback onTap;
  const _FixMarkLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.edit_calendar_outlined,
            size: 15, color: Palette.violet),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            l.t('cyc_future_mark_fix'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Palette.violetText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
        ),
        const Icon(Icons.chevron_right_rounded,
            size: 16, color: Palette.violetText),
      ]),
    );
  }
}

class _ExpectingLink extends StatelessWidget {
  final VoidCallback onTap;
  const _ExpectingLink({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.pregnant_woman_rounded,
            size: 15, color: Palette.violet),
        const SizedBox(width: 4),
        // Flexible because this label is a sentence, not a word, and it is
        // longest in Kazakh — where it ran 173px past the row at 360dp. A
        // MainAxisSize.min row gives a rigid Text no room to shrink into.
        Flexible(
          child: Text(
            l.t('cyc_expecting'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Palette.violetText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

/// 7-day horizontal strip centred on today, each day a soft chip; today is
/// highlighted, logged days carry a dot.
class _WeekStrip extends StatelessWidget {
  final DateTime today;
  final Map<String, DayLog> logs;

  /// Due date, when there is one. Present means each chip also carries the DAY
  /// OF PREGNANCY — day 77, not just "the 22nd".
  ///
  /// That number is the difference between a calendar and a pregnancy
  /// calendar. "Week 11" is what she tells people; the running day count is
  /// what makes the strip feel like it is counting toward something.
  final DateTime? dueDate;

  const _WeekStrip({required this.today, required this.logs, this.dueDate});

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final days = [for (var i = -3; i <= 3; i++) addDays(today, i)];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in days)
          _DayChip(
            weekday: ml.narrowWeekdays[d.weekday % 7],
            day: d.day,
            // Null before conception and past term, where a day number would
            // be meaningless rather than merely large.
            gestDay: _gestDayFor(d),
            isToday: isSameDay(d, today),
            logged: (logs[dateKey(d)]?.isNotEmpty) ?? false,
          ),
      ],
    );
  }

  int? _gestDayFor(DateTime d) {
    final due = dueDate;
    if (due == null) return null;
    final g = gestationFor(due, d);
    if (g == null) return null;
    // gestationFor clamps to 0..300; the clamp is what a day outside the
    // pregnancy looks like, so treat the ends as "no number" rather than
    // printing the clamp back at her.
    if (g.totalDays <= 0 || g.totalDays >= 300) return null;
    return g.totalDays;
  }
}

class _DayChip extends StatelessWidget {
  final String weekday;
  final int day;
  final bool isToday;
  final bool logged;

  /// Day of pregnancy, or null when there is no due date or the day falls
  /// outside it.
  final int? gestDay;

  const _DayChip({
    required this.weekday,
    required this.day,
    required this.isToday,
    required this.logged,
    this.gestDay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(weekday,
            style: const TextStyle(
                color: Palette.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        // The running day count, above the date. Reserve the line either way
        // so the seven chips keep a common baseline — without it the strip
        // shifts vertically the moment one day falls outside the pregnancy.
        SizedBox(
          height: 13,
          child: gestDay == null
              ? null
              : Text('$gestDay',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isToday
                        ? Palette.roseDeep
                        : Palette.textDim.withValues(alpha: 0.7),
                  )),
        ),
        const SizedBox(height: 2),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            // Today is a solid coral disc; every other day is white. Both carry
            // the ink outline, so "today" is signalled by fill rather than by
            // the presence of an edge.
            //
            // This was a two-stop gradient of darkened accents — the darkening
            // was there because the chip prints WHITE text and the original
            // pastel stops measured 3.58:1. Ds.coralCta is the token that
            // already guarantees white-on-it clears 4.5:1, so the workaround
            // goes with the gradient.
            color: isToday ? Ds.coralCta : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
          ),
          alignment: Alignment.center,
          child: Text('$day',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isToday ? Colors.white : Palette.text,
              )),
        ),
        const SizedBox(height: 4),
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: logged ? Palette.rose : Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

/// Elegant, low-profile month grid. Days with logged metrics show a soft pastel
/// circle; today is ringed. Tapping any day opens the logging drawer.

/// Two-letter weekday name for column [dowIndex] (0 = Sunday, Material's order).
///
/// MaterialLocalizations only offers narrowWeekdays, which in Russian is a
/// single letter: В П В С Ч П С. Three pairs collide, so the header cannot be
/// read on its own — you have to count columns to know whether В is Tuesday or
/// Sunday. intl's short names are unambiguous and already localised.
/// The column header for a weekday, index 0 = Sunday.
///
/// From OUR catalogue rather than DateFormat, which reads Intl's GLOBAL locale
/// — something this app never sets. A Russian screen was headed
/// «Mo Tu We Th Fr Sa Su» under «август 2026 г.». See cal_dow_* for why the
/// platform's narrow names are not usable either.
String _weekdayLabel(L10n l, int dowIndex) => l.t('cal_dow_$dowIndex');


/// Which column the 1st of the month falls in, given the locale's first weekday.
///
/// Pure so the arithmetic can be tested without a widget. It was inline and
/// Sunday-first (`first.weekday % 7`), which put every date one column left of
/// where a Russian or Kazakh reader expects it.
///
/// [firstDayOfWeekIndex] is Material's: 0 = Sunday, 1 = Monday. DateTime.weekday
/// is 1..7 with Monday = 1 and Sunday = 7.
int leadingBlanksFor(DateTime firstOfMonth, int firstDayOfWeekIndex) =>
    (firstOfMonth.weekday % 7 - firstDayOfWeekIndex + 7) % 7;

class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final Map<String, DayLog> logs;
  final CycleInfo? cycle; // non-null in cycle mode → colour by cycle phase
  final Set<String> appointmentDays; // dateKeys with a reminder → dot marker
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final void Function(DateTime day) onTapDay;
  const _MonthCalendar({
    super.key,
    required this.month,
    required this.today,
    required this.logs,
    required this.onPrev,
    required this.onNext,
    required this.onTapDay,
    this.cycle,
    this.appointmentDays = const {},
  });

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final l = L10nScope.of(context);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // The week starts where the LOCALE says it starts.
    //
    // This was `first.weekday % 7`, which is Sunday-first — the US convention.
    // Russian and Kazakh weeks start on Monday, so every date sat one column to
    // the left of where a reader here expects it, under a header that also
    // began at Sunday. The numbers were right and the shape of the month was
    // wrong, which is the kind of error you feel rather than notice.
    //
    // firstDayOfWeekIndex is 1 (Monday) for ru/kk and 0 for en_US, so this
    // stays correct if the app is ever read in another locale.
    final firstDow = ml.firstDayOfWeekIndex;
    // DateTime.weekday is 1..7 (Mon..Sun); narrowWeekdays is indexed 0..6
    // (Sun..Sat). This maps a date to its column under the rotated header.
    final leadingBlanks = leadingBlanksFor(first, firstDow);
    final cells = leadingBlanks + daysInMonth;
    final rows = (cells / 7).ceil();

    return DsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrev,
                tooltip: ml.previousMonthTooltip,
                icon: const Icon(Icons.chevron_left, color: Palette.textDim),
              ),
              Expanded(
                child: Text(ml.formatMonthYear(month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: onNext,
                tooltip: ml.nextMonthTooltip,
                icon: const Icon(Icons.chevron_right, color: Palette.textDim),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Rotated to start on the locale's first day, and TWO letters.
              // The single-letter Russian narrow names are В П В С Ч П С — two
              // Вs, two Пs and two Сs, so three of the seven columns cannot be
              // told apart from their header alone.
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                      _weekdayLabel(l, (firstDow + i) % 7),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          // The weekend reads differently from the working week
                          // at a glance, which is most of what a month grid is
                          // scanned for.
                          color: ((firstDow + i) % 7 == 0 || (firstDow + i) % 7 == 6)
                              ? Palette.textDim.withValues(alpha: 0.75)
                              : Palette.textDim,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                        child: _buildCell(
                            r * 7 + col - leadingBlanks + 1, daysInMonth)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(int dayNum, int daysInMonth) {
    if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox(height: 40);
    final date = DateTime(month.year, month.month, dayNum);
    final log = logs[dateKey(date)];
    final logged = log?.isNotEmpty ?? false;
    final isToday = isSameDay(date, today);
    final isFuture = date.isAfter(today);
    final hasAppointment = appointmentDays.contains(dateKey(date));

    // Colour resolution: cycle phase (cycle mode) wins, else the generic
    // "something logged" pink dot.
    Color fill = Colors.transparent;
    Color? textColor;
    Color borderColor = Palette.violet;
    if (cycle != null) {
      final type =
          cycleDayType(date, cycle!, loggedPeriod: log?.hasPeriod ?? false);
      final s = cycleCellStyle(type);
      fill = s.fill;
      textColor = s.text;
    } else if (logged) {
      fill = Palette.rose.withValues(alpha: 0.16);
      textColor = Palette.roseDeep;
    }

    return Semantics(
      button: !isFuture,
      child: GestureDetector(
        onTap: isFuture
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTapDay(date);
              },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          // 48, not 40: this is the minimum touch target on both platforms, and
          // these cells were below it. The visible circle stays 34 — only the
          // hit area grows, so nothing looks different but the day someone is
          // aiming for is the day they get.
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: isToday
                      ? Border.all(color: borderColor, width: 1.6)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text('$dayNum',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      color: textColor ??
                          (isFuture
                              ? Palette.textDim.withValues(alpha: 0.5)
                              : Palette.text),
                    )),
              ),
              // Appointment marker: a small amber dot at the bottom of the cell,
              // bordered so it stays visible on filled (period/ovulation) days.
              if (hasAppointment)
                Positioned(
                  bottom: 1,
                  child: Container(
                    key: ValueKey('appt-dot-$dayNum'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Palette.amber,
                      shape: BoxShape.circle,
                      border: Border.all(color: Palette.surface, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fill + text colour for each cycle day type in the month grid.
({Color fill, Color? text}) cycleCellStyle(CycleDayType type) => switch (type) {
      CycleDayType.period => (fill: Palette.roseDeep, text: Colors.white),
      CycleDayType.predictedPeriod => (
          fill: Palette.rose.withValues(alpha: 0.18),
          text: Palette.roseDeep
        ),
      CycleDayType.ovulation => (fill: Palette.teal, text: Colors.white),
      CycleDayType.fertile => (
          fill: Palette.teal.withValues(alpha: 0.16),
          text: Palette.teal
        ),
      CycleDayType.none => (fill: Colors.transparent, text: null),
    };

/// The third-trimester hospital-bag entry: how much is packed, and a tap to the
/// checklist.
class _HospitalBagCard extends StatelessWidget {
  final Set<String> checked;
  final VoidCallback onOpen;
  const _HospitalBagCard({required this.checked, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final done = isFullyPacked(checked);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Palette.rose.withValues(alpha: 0.14),
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                  color: Palette.roseDeep.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                    done ? Icons.check_circle_rounded : Icons.luggage_outlined,
                    color: done ? Palette.teal : Palette.roseDeep,
                    size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('bag_card_title'),
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      done
                          ? l.t('bag_done')
                          : l.t('bag_packed', {
                              'n': packedCount(checked),
                              'total': hospitalBagTotal
                            }),
                      style: const TextStyle(
                          color: Palette.textDim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _PregnancyMilestones extends StatelessWidget {
  final int week;
  const _PregnancyMilestones({required this.week});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final current = currentMilestone(week);
    final next = nextMilestone(week);
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('gest_milestones').toUpperCase(),
              style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 12),
          _MilestoneRow(
            icon: Icons.flag_rounded,
            color: Palette.violet,
            label: l.t(current.code),
            badge: l.t('ms_now'),
            badgeColor: Palette.violet,
          ),
          if (next != null) ...[
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Palette.border)),
            _MilestoneRow(
              icon: Icons.outlined_flag_rounded,
              color: Palette.rose,
              label: l.t(next.code),
              badge: l.t('ms_next_in', {'n': weeksUntil(week, next)}),
              badgeColor: Palette.roseDeep,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared history-card header: an uppercase title + a small clear-all action.
class _HistoryHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClear;
  const _HistoryHeader({required this.title, required this.onClear});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
        ),
        InkWell(
          onTap: onClear,
          borderRadius: BorderRadius.circular(8),
          // A destructive action needs a deliberate, full-size target.
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Text(l.t('hist_clear'),
                style: const TextStyle(
                    color: Palette.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

/// Recent timed kick sessions: count · duration · when. Newest first, capped to
/// a short list so the pregnancy view stays scannable.
class _KickHistory extends StatelessWidget {
  final List<KickSessionRecord> sessions;
  final DateTime today;
  final VoidCallback onClear;
  final VoidCallback onOpenAll;
  const _KickHistory(
      {required this.sessions,
      required this.today,
      required this.onClear,
      required this.onOpenAll});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final shown = sessions.take(5).toList();
    final summary = kickHistorySummary(sessions);
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HistoryHeader(title: l.t('kick_history'), onClear: onClear),
          if (summary.sessions >= 2) ...[
            const SizedBox(height: 12),
            _KickSummaryStrip(summary: summary),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: Palette.border)),
            _KickHistoryRow(record: shown[i], now: today),
          ],
          if (sessions.length > shown.length)
            _SeeAllRow(count: sessions.length, onTap: onOpenAll),
        ],
      ),
    );
  }
}

/// A generic full-history screen: a titled list of pre-built rows.
class SessionHistoryScreen extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const SessionHistoryScreen(
      {super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(title)),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) => DsCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: rows[i]),
        ),
      ),
    );
  }
}

class _SeeAllRow extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _SeeAllRow({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(l.t('hist_see_all', {'n': count}),
                  style: const TextStyle(
                      color: Palette.violetText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Palette.violet),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact three-stat strip summarizing kick history: avg movements, avg length,
/// and how many sessions met the goal.
class _KickSummaryStrip extends StatelessWidget {
  final KickHistorySummary summary;
  const _KickSummaryStrip({required this.summary});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        color: Palette.violet.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _KickSummaryStat(
              value: summary.avgCount
                  .toStringAsFixed(summary.avgCount % 1 == 0 ? 0 : 1),
              label: l.t('kick_avg_count')),
          _kickDivider(),
          _KickSummaryStat(
              value: formatElapsed(summary.avgDuration),
              label: l.t('kick_avg_length')),
          _kickDivider(),
          _KickSummaryStat(
              value: '${summary.goalReached}/${summary.sessions}',
              label: l.t('kick_goal_hits')),
        ],
      ),
    );
  }

  Widget _kickDivider() =>
      Container(width: 1, height: 30, color: Palette.border);
}

class _KickSummaryStat extends StatelessWidget {
  final String value;
  final String label;
  const _KickSummaryStat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Palette.text)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.textDim, fontSize: 11)),
          ],
        ),
      );
}

class _KickHistoryRow extends StatelessWidget {
  final KickSessionRecord record;
  final DateTime now;
  const _KickHistoryRow({required this.record, required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final age = now.difference(record.endedAt);
    // NO TICK HERE ANY MORE, and its absence is the ruling of 2026-08-19.
    // Every session with ten or more movements ended this row with a green
    // `Icons.check_rounded` in `Palette.good` — a wordless «all good» on a
    // fetal-movement count, on a screen whose cited protocol («Антенатальный
    // уход», RK MOH 2025) says that count predicts nothing. It carried no
    // string, so no fingerprint and no token guard could ever have caught it;
    // it was found by reading the widget beside `kick_goal_hits`.
    //
    // Nothing takes its place. The row already states what happened — the count
    // and how long it took — and the strip above it gives the tally. See
    // docs/CLINICAL-REVIEW-WATCH.md, «kick_goal_reached — REFUSED as written».
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: Ds.coralCta,
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.child_care_rounded,
              size: 18, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('kick_history_count', {'n': record.count}),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  '${formatElapsed(record.duration)} · ${l.ago(age.isNegative ? Duration.zero : age)}',
                  style:
                      const TextStyle(color: Palette.textDim, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Recent contraction sessions: count · average interval · when.
class _ContractionHistory extends StatelessWidget {
  final List<ContractionSessionRecord> sessions;
  final DateTime today;
  final VoidCallback onClear;
  final VoidCallback onOpenAll;
  const _ContractionHistory(
      {required this.sessions,
      required this.today,
      required this.onClear,
      required this.onOpenAll});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final shown = sessions.take(5).toList();
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HistoryHeader(title: l.t('contr_history'), onClear: onClear),
          const SizedBox(height: 12),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: Palette.border)),
            _ContractionHistoryRow(record: shown[i], now: today),
          ],
          if (sessions.length > shown.length)
            _SeeAllRow(count: sessions.length, onTap: onOpenAll),
        ],
      ),
    );
  }
}

class _ContractionHistoryRow extends StatelessWidget {
  final ContractionSessionRecord record;
  final DateTime now;
  const _ContractionHistoryRow({required this.record, required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final age = now.difference(record.endedAt);
    final interval =
        record.avgIntervalSec > 0 ? formatElapsed(record.avgInterval) : '—';
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: Palette.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10)),
          child:
              const Icon(Icons.timer_outlined, size: 18, color: Palette.violet),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('contr_history_count', {'n': record.count}),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  '${l.t('contr_history_interval', {
                        'i': interval
                      })} · ${l.ago(age.isNegative ? Duration.zero : age)}',
                  style:
                      const TextStyle(color: Palette.textDim, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String badge;
  final Color badgeColor;
  const _MilestoneRow(
      {required this.icon,
      required this.color,
      required this.label,
      required this.badge,
      required this.badgeColor});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20)),
          child: Text(badge,
              style: TextStyle(
                  color: darkenForText(badgeColor),
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ),
      ],
    );
  }
}

/// A labelled slider row for the cycle-settings sheet.
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;
  const _SliderRow(
      {required this.label,
      required this.value,
      required this.min,
      required this.max,
      required this.display,
      required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(display,
              style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w700,
                  color: Palette.roseDeep)),
        ]),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round(),
          activeColor: Palette.roseDeep,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Current cycle-phase card: which of the four phases today falls in, the day
/// within that phase, and a short educational note. Colour-coded per phase.
class _CyclePhaseCard extends StatelessWidget {
  final CycleInfo info;
  const _CyclePhaseCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final phase = cyclePhaseFor(info);
    if (phase == null) return const SizedBox.shrink();
    final (name, color, icon) = switch (phase.phase) {
      CyclePhase.menstrual => (
          l.t('phase_menstrual'),
          Palette.roseDeep,
          Icons.water_drop_rounded
        ),
      CyclePhase.follicular => (
          l.t('phase_follicular'),
          Palette.violet,
          Icons.eco_rounded
        ),
      CyclePhase.fertile => (
          l.t('phase_fertile'),
          Palette.teal,
          Icons.brightness_high_rounded
        ),
      CyclePhase.luteal => (
          l.t('phase_luteal'),
          Palette.amber,
          Icons.nightlight_round
        ),
    };
    final note = l.t('phase_${phase.phase.name}_note');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wrap, not Row: «Фолликулярная фаза» plus «День 11 из 12»
                // overflowed this line by 131px at 402dp — a striped bar across
                // the card for every user with a period logged, in Russian, on
                // a phone WIDER than the narrow sweep's. It was never rendered:
                // both the golden and `narrow_phone_test` build cycle mode from
                // a controller with no logs, so no phase card exists in either.
                // A Wrap drops the pill to its own line instead of clipping,
                // and cannot overflow at any width or text scale.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: Ds.ink, width: DsShape.borderWidth),
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(
                          l.t('phase_day',
                              {'n': phase.dayInPhase, 'of': phase.phaseLength}),
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(note,
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Around now you often log…" — the symptoms this user has historically logged
/// during the phase they're in. Forward-looking and personal; not a prediction.
class _UsualSymptomsCard extends StatelessWidget {
  final List<({Symptom symptom, int count})> symptoms;
  const _UsualSymptomsCard({required this.symptoms});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final top = symptoms.take(3).toList();
    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                color: Palette.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.lightbulb_outline_rounded,
                color: Palette.amber, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('cyc_usual_title'),
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Palette.text)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in top)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Palette.amber.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Palette.amber.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                            '${l.t('sym_${s.symptom.name}')} · ${s.count}×',
                            style: const TextStyle(
                                color: Palette.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A heads-up before the fertile window opens: "Fertile window in N days ·
/// ovulation in M days". Only shown while the window is still upcoming (the
/// phase card covers it once it's active).
class _FertileCountdownCard extends StatelessWidget {
  final FertileCountdown countdown;
  const _FertileCountdownCard({required this.countdown});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Palette.teal.withValues(alpha: 0.12),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                color: Palette.teal.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.eco_rounded, color: Palette.teal, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('cyc_fertile_in', {'n': countdown.daysToStart}),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Palette.teal,
                        height: 1.2)),
                const SizedBox(height: 3),
                Text(l.t('cyc_ovulation_in', {'n': countdown.daysToOvulation}),
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Predictions summary (cycle mode): next-period date + delay status, fertile
/// window dates, and ovulation date — the "when is my next period / am I late"
/// answers the calendar colours only hint at.
class _CyclePredictions extends StatelessWidget {
  final CycleInfo info;
  final PredictionConfidence confidence;

  /// Whether the cycle length under these dates is one SHE chose, in the
  /// settings sheet, rather than the app's 28.
  ///
  /// [AppController.cycleBaselineDays] is nullable precisely so this can be
  /// told apart, and until now that knowledge stopped at the profile sync.
  /// It only matters while [CycleInfo.avgCycleMeasured] is false: once real
  /// gaps exist they outvote the baseline and the line states a measurement.
  final bool baselineChosen;

  const _CyclePredictions(
      {required this.info,
      required this.confidence,
      required this.baselineChosen});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    final until = info.daysUntilNextPeriod ?? 0;
    final (statusText, statusColor) = until > 0
        ? (l.t('cyc_period_in', {'n': until}), Palette.roseDeep)
        : until == 0
            ? (l.t('cyc_period_today'), Palette.roseDeep)
            : (l.t('cyc_period_late', {'n': -until}), Palette.amber);

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('cyc_predictions').toUpperCase(),
              style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 12),
          _PredRow(
            icon: Icons.water_drop_rounded,
            color: Palette.roseDeep,
            label: l.t('cyc_next_period'),
            value: ml.formatMediumDate(info.nextPeriodStart!),
            badge: statusText,
            badgeColor: statusColor,
          ),
          const _PredDivider(),
          _PredRow(
            icon: Icons.eco_rounded,
            color: Palette.teal,
            label: l.t('cyc_phase_fertile'),
            value:
                '${ml.formatMediumDate(info.fertileStart!)} – ${ml.formatMediumDate(info.fertileEnd!)}',
          ),
          const _PredDivider(),
          _PredRow(
            icon: Icons.brightness_high_rounded,
            color: Palette.teal,
            label: l.t('cyc_ovulation'),
            value: ml.formatMediumDate(info.ovulation!),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                // THE AVERAGE, OR THE ASSUMPTION STANDING IN FOR IT.
                //
                // This printed «Средний цикл: 28 дн.» after ONE logged period —
                // a stated average over zero completed cycles. The chip to the
                // right says «мало данных», which is the right hedge on the
                // DATES; it does not excuse a measurement claim beside it.
                //
                // The dates are kept. They rest on a number, they always did,
                // and withholding them would leave the card with nothing on the
                // one screen a period tracker exists for. What was missing is
                // that the number was never named as an assumption — so the
                // line now names it, and says whose it is.
                child: Text(
                    info.avgCycleMeasured
                        ? l.t('cyc_avg_cycle', {'n': info.avgCycleLength})
                        : l.t(
                            baselineChosen
                                ? 'cyc_avg_cycle_setting'
                                : 'cyc_avg_cycle_assumed',
                            {'n': info.avgCycleLength}),
                    style:
                        const TextStyle(color: Palette.textDim, fontSize: 12)),
              ),
              _ConfidenceChip(confidence: confidence),
            ],
          ),
        ],
      ),
    );
  }
}

/// How much history backs the predictions — a small honesty cue so early
/// forecasts aren't over-trusted.
class _ConfidenceChip extends StatelessWidget {
  final PredictionConfidence confidence;
  const _ConfidenceChip({required this.confidence});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final (color, label) = switch (confidence) {
      PredictionConfidence.low => (Palette.textDim, l.t('cyc_conf_low')),
      PredictionConfidence.building => (
          Palette.amber,
          l.t('cyc_conf_building')
        ),
      // Amber like 'building' — the date is equally approximate — but the
      // words say why, and that logging more will not sharpen it.
      PredictionConfidence.variable => (
          Palette.amber,
          l.t('cyc_conf_variable')
        ),
      PredictionConfidence.good => (Palette.good, l.t('cyc_conf_good')),
    };
    return Tooltip(
      message: l.t('cyc_conf_tip'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insights_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _PredRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? badge;
  final Color? badgeColor;
  const _PredRow(
      {required this.icon,
      required this.color,
      required this.label,
      required this.value,
      this.badge,
      this.badgeColor});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        // THE BADGE SITS WITH THE DATE, NOT AT THE FAR RIGHT.
        //
        // Incidental to §10.9 and found by the test written for it: this row
        // overflowed by 70 px at 320 dp with the font slider at 130 % in
        // Kazakh, where «через 12 дней» is «12 күннен кейін». The badge was an
        // inflexible child, so it took its natural width first and the Expanded
        // column was left with whatever remained — which was less than nothing.
        //
        // Nothing in the suite had ever drawn it. The golden builds cycle mode
        // from an EMPTY controller and narrow_phone_test measures a 640 dp
        // fold, and this card is far below it in a `ListView(children:)` that
        // mounts only what is near the viewport. Exactly the vacuity that hid a
        // 131 px overflow in _CyclePhaseCard until 359fb8d, one card up.
        //
        // A Wrap, reusing that fix's answer rather than inventing a third: the
        // badge follows the date on one line while there is room and drops
        // under it when there is not. It also reads better — «через 12 дней»
        // qualifies the date, and pinning it to the opposite edge of the card
        // put the whole row's width between the two halves of one statement.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(color: Palette.textDim, fontSize: 12.5)),
              const SizedBox(height: 1),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: Ds.ink, width: DsShape.borderWidth),
                          color: badgeColor!.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(badge!,
                          style: TextStyle(
                              color: badgeColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PredDivider extends StatelessWidget {
  const _PredDivider();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: Palette.border));
}

/// Legend for the cycle calendar colours.
class _CycleLegend extends StatelessWidget {
  const _CycleLegend();
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _LegendDot(color: Palette.roseDeep, label: l.t('cyc_period')),
        _LegendDot(
            color: Palette.rose.withValues(alpha: 0.5),
            label: l.t('cyc_predicted')),
        _LegendDot(
            color: Palette.teal.withValues(alpha: 0.5),
            label: l.t('cyc_fertile')),
        _LegendDot(color: Palette.teal, label: l.t('cyc_ovulation')),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
    ]);
  }
}

/// The "what is the baby called?" dialog.
///
/// A StatefulWidget so the TextEditingController lives and dies with the route.
/// Created in the calling function and disposed after showDialog returned, it
/// was disposed while the dialog's exit animation still held it — and the next
/// frame threw "A TextEditingController was used after being disposed".
class _BirthNameDialog extends StatefulWidget {
  final String title;
  final String label;
  final String save;
  const _BirthNameDialog(
      {required this.title, required this.label, required this.save});

  @override
  State<_BirthNameDialog> createState() => _BirthNameDialogState();
}

class _BirthNameDialogState extends State<_BirthNameDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          // One button, going forward. An empty name is a supported answer, so
          // there is nothing here to cancel — and a Cancel would throw away the
          // birth date she just picked.
          TextButton(
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: Text(widget.save),
          ),
        ],
      );
}
