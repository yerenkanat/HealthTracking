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
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import '../../app/app_controller.dart';
import '../../domain/birth_transition.dart';
import '../../domain/cycle_log.dart';
import '../../domain/contraction.dart';
import '../../domain/cycle_insights.dart'
    show cycleHistory, cycleRegularity, predictionConfidence, symptomsInPhase, PredictionConfidence;
import '../../domain/cycle_predictions.dart';
import '../../domain/kick_session.dart';
import '../../domain/baby_size.dart';
import '../../domain/fetal_development.dart';
import '../../domain/postpartum.dart';
import '../../domain/pregnancy_milestones.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';
import 'baby_size_disc.dart';
import 'contraction_timer_screen.dart';
import 'postpartum_screen.dart';
import 'pregnancy_warnings.dart';
import 'pregnancy_weight_screen.dart';
import '../../domain/weight.dart';
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
import 'week_detail_screen.dart';

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

class _WomensHealthScreenState extends State<WomensHealthScreen> {
  late DateTime _month; // first day of the visible month
  late DateTime _today;

  @override
  void initState() {
    super.initState();
    _today = _dayOnly(widget.now());
    _month = DateTime(_today.year, _today.month, 1);
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

  void _shiftMonth(int by) => setState(() => _month = DateTime(_month.year, _month.month + by, 1));

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = widget.controller;
    return StreamBuilder<void>(
      stream: c.changes,
      builder: (context, _) {
        final cycleMode = !c.isPregnant;
        final periodToday = c.logFor(_today).hasPeriod;
        return AuroraBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: FittedTitle(l.t('cal_screen_title')),
              actions: [
                if (!cycleMode)
                  IconButton(
                    icon: const Icon(Icons.timer_outlined),
                    tooltip: l.t('contr_title'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ContractionTimerScreen(
                        onSave: (count, dur, interval) => c.logContractionSession(count, dur, interval),
                      )),
                    ),
                  ),
                // Safety content, always one tap from the main pregnancy view —
                // not buried inside a week's detail. Same card, shown here on
                // its own screen.
                if (!cycleMode)
                  IconButton(
                    icon: const Icon(Icons.health_and_safety_outlined),
                    tooltip: l.t('preg_warn_title'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PregnancyWarningsScreen()),
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
                    MaterialPageRoute(builder: (_) => MedicationsScreen(controller: c, now: () => _today)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.insights_rounded),
                  tooltip: l.t('cyc_insights_title'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CycleInsightsScreen(controller: c)),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            // Quick, discoverable one-tap period logging (cycle mode only).
            floatingActionButton: cycleMode
                ? FloatingActionButton.extended(
                    onPressed: _logPeriodToday,
                    // White label on roseDeep measures 3.58:1. Darkened so the
                    // most-used control on this screen is legible.
                    backgroundColor: darkenForText(Palette.roseDeep),
                    foregroundColor: Colors.white,
                    icon: Icon(periodToday ? Icons.check_rounded : Icons.water_drop_rounded),
                    label: Text(l.t(periodToday ? 'cyc_period_logged' : 'cyc_log_period')),
                  )
                : null,
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
              children: [
                if (cycleMode)
                  _CycleHeader(controller: c, today: _today, onSetDueDate: _pickDueDate)
                else
                  _GestationHeader(controller: c, today: _today, onSetDueDate: _pickDueDate),

                // After a recent birth the app is in cycle mode but her body is
                // still recovering. Surface the recovery guide until the window
                // passes — the one place the app speaks to the mother, not the
                // baby, in these weeks.
                if (cycleMode) ...[
                  if (_recentBirth(c) case final birth?) ...[
                    const SizedBox(height: 14),
                    _PostpartumCard(
                      birthDate: birth,
                      today: _today,
                      onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PostpartumScreen(birthDate: birth, today: _today),
                      )),
                    ),
                  ],
                ],

                // Daily tips, right under the pregnancy hero — the same
                // published catalogue the dashboard shows, keyed to her week.
                // Only in pregnancy mode: the cycle calendar has its own
                // content elsewhere, and showing an empty shelf on it would be
                // clutter. Hidden entirely when nothing is wired.
                if (!cycleMode && c.isPregnant && widget.onOpenTip != null) ...[
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
                if (cycleMode && c.cycle.hasData) ...[
                  const SizedBox(height: 14),
                  _CyclePhaseCard(info: c.cycle),
                  if (cyclePhaseFor(c.cycle) case final ph?)
                    Builder(builder: (_) {
                      final usual = symptomsInPhase(c.dayLogs.values, c.periodDays, ph.phase);
                      if (usual.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _UsualSymptomsCard(symptoms: usual),
                      );
                    }),
                  if (fertileCountdown(c.cycle)?.state == FertileWindowState.upcoming) ...[
                    const SizedBox(height: 14),
                    _FertileCountdownCard(countdown: fertileCountdown(c.cycle)!),
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
                    );
                  }),
                ],
                if (!cycleMode && c.gestation != null) ...[
                  const SizedBox(height: 14),
                  _BabySizeCard(week: c.gestation!.week),
                  const SizedBox(height: 14),
                  _PregnancyMilestones(week: c.gestation!.week),
                ],
                if (!cycleMode) ...[
                  const SizedBox(height: 14),
                  WeightCard(
                    entries: c.weights,
                    onLog: (kg) => c.logWeight(_today, kg),
                    goalKg: c.weightGoalKg,
                    onSetGoal: c.setWeightGoal,
                    onOpenHistory: c.weights.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => WeightHistoryScreen(entries: c.weights, onDelete: c.removeWeightEntry),
                    )),
                    // Pregnancy only: how much is healthy to gain, and how her
                    // logged pace compares.
                    onOpenGuide: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PregnancyWeightScreen(weeklyRateKg: weeklyGainRate(c.weights)),
                    )),
                  ),
                ],
                if (c.medications.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  MedicationCard(
                    controller: c,
                    today: _today,
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MedicationsScreen(controller: c, now: () => _today),
                    )),
                  ),
                ],
                const SizedBox(height: 16),
                _MonthCalendar(
                  month: _month,
                  today: _today,
                  logs: c.dayLogs,
                  cycle: cycleMode ? c.cycle : null,
                  appointmentDays: {for (final a in c.appointments) dateKey(a.at)},
                  onPrev: () => _shiftMonth(-1),
                  onNext: () => _shiftMonth(1),
                  onTapDay: _openDay,
                ),
                if (cycleMode && c.cycle.hasData) ...[
                  const SizedBox(height: 14),
                  const _CycleLegend(),
                ],
                if (!cycleMode && c.kickSessions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _KickHistory(sessions: c.kickSessions, today: _today,
                      onClear: () => _clearHistory(title: l.t('kick_history_clear_title'), onConfirmed: c.clearKickSessions),
                      onOpenAll: () => _openFullHistory(l.t('kick_history'),
                          [for (final s in c.kickSessions) _KickHistoryRow(record: s, now: _today)])),
                ],
                if (!cycleMode && c.contractionSessions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ContractionHistory(sessions: c.contractionSessions, today: _today,
                      onClear: () => _clearHistory(title: l.t('contr_history_clear_title'), onConfirmed: c.clearContractionSessions),
                      onOpenAll: () => _openFullHistory(l.t('contr_history'),
                          [for (final s in c.contractionSessions) _ContractionHistoryRow(record: s, now: _today)])),
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

  Future<void> _clearHistory({required String title, required VoidCallback onConfirmed}) async {
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
    final text = buildCycleSummary(l, info, formatDate: ml.formatMediumDate);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('cyc_share_copied')), behavior: SnackBarBehavior.floating),
    );
  }

  void _openCycleSettings() {
    final c = widget.controller;
    var cycleLen = c.avgCycleLength.toDouble();
    var periodLen = c.avgPeriodLength.toDouble();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) {
        final l = L10nScope.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(
                left: 20, right: 20, top: 16, bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(l.t('cyc_settings_title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(l.t('cyc_settings_hint'), style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                const SizedBox(height: 18),
                _SliderRow(
                  label: l.t('cyc_avg_cycle_label'),
                  value: cycleLen, min: 21, max: 35,
                  display: l.t('cyc_days_short', {'n': cycleLen.round()}),
                  onChanged: (v) => setSheet(() => cycleLen = v),
                ),
                const SizedBox(height: 12),
                _SliderRow(
                  label: l.t('cyc_avg_period_label'),
                  value: periodLen, min: 2, max: 8,
                  display: l.t('cyc_days_short', {'n': periodLen.round()}),
                  onChanged: (v) => setSheet(() => periodLen = v),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.notifications_outlined, size: 18, color: Palette.textDim),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.t('rem_manage_hint'),
                          style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    c.setCycleBaseline(cycle: cycleLen.round(), period: periodLen.round());
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
      action: SnackBarAction(label: l.t('act_remove'), onPressed: () => c.toggleFlowFor(_today, Flow.medium)),
    ));
  }

  Future<void> _pickDueDate() async {
    final c = widget.controller;
    final initial = c.dueDate ?? _today.add(const Duration(days: 140)); // elapsed-ok: a picker default, adjustable by hand
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _today.subtract(const Duration(days: 300)), // elapsed-ok: a generous picker bound
      lastDate: _today.add(const Duration(days: 300)), // elapsed-ok: a generous picker bound
      helpText: L10nScope.of(context).t('cal_due_pick'),
    );
    if (picked != null) c.setDueDate(picked);
  }

  void _openDay(DateTime day) => showDayLogSheet(context, widget.controller, day);
}

/// Gestation header: a "Week N, Day D" progress card + a 7-day horizontal strip
/// centred on today. When no due date is set, invites the mother to add one.
class _GestationHeader extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  final VoidCallback onSetDueDate;
  const _GestationHeader({required this.controller, required this.today, required this.onSetDueDate});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final g = controller.gestation;

    if (g == null) {
      return GlassCard(
        onTap: onSetDueDate,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: const BoxDecoration(gradient: Palette.roseViolet, shape: BoxShape.circle),
              child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('cal_no_due_title'),
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(l.t('cal_no_due_body'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
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
          onDetails: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WeekDetailScreen(gestation: g),
          )),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Both sides flex and ellipsise. A long localized date plus the
            // end-pregnancy link overflowed a narrow phone by 128px, and a
            // layout exception blanks everything below it — which is how the
            // tips shelf under this header stopped rendering in the test.
            Flexible(
              child: GestureDetector(
                onTap: onSetDueDate,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.edit_calendar_outlined, size: 15, color: Palette.violet),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      controller.dueDate != null
                          ? l.t('gest_due', {
                              'date': MaterialLocalizations.of(context).formatMediumDate(controller.dueDate!)
                            })
                          : l.t('cal_no_due_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Palette.violetText, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _confirmEndPregnancy(context),
              child: Text(l.t('cyc_end_pregnancy'),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12, decoration: TextDecoration.underline)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _WeekStrip(today: today, logs: controller.dayLogs, dueDate: controller.dueDate),
      ],
    );
  }

  /// Gentle, neutral confirmation before switching out of pregnancy mode.
  /// Not styled as destructive — logged data is kept, and the wording is soft.
  /// End-of-pregnancy fork.
  ///
  /// This used to be one yes/no dialog that cleared the due date. Two entirely
  /// different events came through it: a birth, and a loss.
  ///
  /// For the birth it threw away the date the whole second half of the app is
  /// keyed on — the development calendar, the vaccinations, the growth chart —
  /// leaving a woman to add a child by hand and retype it days after giving
  /// birth. For a loss, the same door has to say nothing cheerful at all.
  Future<void> _confirmEndPregnancy(BuildContext context) async {
    final l = L10nScope.of(context);
    final outcome = await showModalBottomSheet<PregnancyOutcome>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 18),
            Text(l.t('birth_which'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.child_friendly_rounded, color: Palette.rose),
              title: Text(l.t('birth_born'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(l.t('birth_born_sub'),
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
              onTap: () => Navigator.pop(ctx, PregnancyOutcome.born),
            ),
            // Deliberately plain. No icon that celebrates, no colour, no
            // follow-up — for the woman taking this path the kindest thing the
            // app can do is get out of the way.
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
    );
    if (!context.mounted || outcome == null) return;

    if (outcome == PregnancyOutcome.ended) {
      controller.setDueDate(null);
      return;
    }
    await _recordBirth(context);
  }

  /// Collect the birth date (and a name, if she has one yet) and create the
  /// child record the calendars need.
  Future<void> _recordBirth(BuildContext context) async {
    final l = L10nScope.of(context);
    final initial = defaultBirthDate(dueDate: controller.dueDate, today: today);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      // A birth cannot be in the future, and 300 days back covers any
      // pregnancy the app was tracking.
      firstDate: addDays(today, -300),
      lastDate: today,
      helpText: l.t('birth_date'),
    );
    if (!context.mounted || date == null) return;

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
    if (!context.mounted || name == null) return;

    final t = birthTransition(
      childId: 'child-${today.microsecondsSinceEpoch}',
      name: name,
      birthDate: date,
      today: today,
    );
    controller.addChild(t.child!);
    controller.setDueDate(null);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('birth_done')), behavior: SnackBarBehavior.floating),
    );
  }
}

/// Cycle header (non-pregnant mode): cycle day + days-to-next-period + phase,
/// with a 7-day strip. Invites the user to log a period when there's no data yet.
class _CycleHeader extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  final VoidCallback onSetDueDate;
  const _CycleHeader({required this.controller, required this.today, required this.onSetDueDate});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final info = controller.cycle;

    if (!info.hasData) {
      return GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Palette.rose, Palette.roseDeep]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.water_drop_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.t('cyc_no_data_title'),
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(l.t('cyc_no_data_body'),
                          style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _ExpectingLink(onTap: onSetDueDate),
          ],
        ),
      );
    }

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
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Palette.rose.withValues(alpha: 0.14), Palette.violet.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: Palette.rose.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              MetricRing(
                fraction: (info.cycleDay ?? 1) / info.avgCycleLength,
                gradient: const LinearGradient(colors: [Palette.rose, Palette.violet]),
                size: 72, stroke: 8,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${info.cycleDay ?? 1}',
                        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
                    Text(l.t('cyc_day_short'), style: const TextStyle(color: Palette.textDim, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    if (_phaseLabel(l, phaseType) != null)
                      _PhasePill(label: _phaseLabel(l, phaseType)!, type: phaseType),
                    const SizedBox(height: 6),
                    _ExpectingLink(onTap: onSetDueDate),
                  ],
                ),
              ),
            ],
          ),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
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
        const Icon(Icons.pregnant_woman_rounded, size: 15, color: Palette.violet),
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
                color: Palette.violetText, fontSize: 12.5, fontWeight: FontWeight.w600),
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
        Text(weekday, style: const TextStyle(color: Palette.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
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
                    color: isToday ? Palette.roseDeep : Palette.textDim.withValues(alpha: 0.7),
                  )),
        ),
        const SizedBox(height: 2),
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            // The today chip carries WHITE text, and white on the pastel end of
            // roseViolet measures 3.58:1 — under the 4.5 minimum. Darkening the
            // stops keeps the gradient look while making the number legible;
            // the accessibility suite checks the result rather than my eye.
            gradient: isToday
                ? LinearGradient(colors: [
                    darkenForText(Palette.rose),
                    darkenForText(Palette.violet),
                  ])
                : null,
            color: isToday ? null : Colors.white,
            shape: BoxShape.circle,
            border: isToday ? null : Border.all(color: Palette.border),
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
          width: 5, height: 5,
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
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday % 7; // 0 = Sunday-first column
    final cells = leadingBlanks + daysInMonth;
    final rows = (cells / 7).ceil();

    return GlassCard(
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
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
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
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(ml.narrowWeekdays[i],
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w600)),
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
                    Expanded(child: _buildCell(r * 7 + col - leadingBlanks + 1, daysInMonth)),
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
      final type = cycleDayType(date, cycle!, loggedPeriod: log?.hasPeriod ?? false);
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
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: isToday ? Border.all(color: borderColor, width: 1.6) : null,
              ),
              alignment: Alignment.center,
              child: Text('$dayNum',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: textColor ?? (isFuture ? Palette.textDim.withValues(alpha: 0.5) : Palette.text),
                  )),
            ),
            // Appointment marker: a small amber dot at the bottom of the cell,
            // bordered so it stays visible on filled (period/ovulation) days.
            if (hasAppointment)
              Positioned(
                bottom: 1,
                child: Container(
                  key: ValueKey('appt-dot-$dayNum'),
                  width: 6, height: 6,
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
      CycleDayType.predictedPeriod => (fill: Palette.rose.withValues(alpha: 0.18), text: Palette.roseDeep),
      CycleDayType.ovulation => (fill: Palette.teal, text: Colors.white),
      CycleDayType.fertile => (fill: Palette.teal.withValues(alpha: 0.16), text: Palette.teal),
      CycleDayType.none => (fill: Colors.transparent, text: null),
    };

/// Pregnancy timeline milestones (non-medical): current stage + what's next.
/// Weekly "baby is about the size of a …" card — an approximate length and a
/// friendly everyday comparison for the current pregnancy week. Illustrative,
/// not medical.
/// The entry to the postpartum recovery guide, shown in cycle mode after a
/// recent birth. Leads with the six-week countdown when there is one, since
/// that is the actionable date.
class _PostpartumCard extends StatelessWidget {
  final DateTime birthDate;
  final DateTime today;
  final VoidCallback onOpen;
  const _PostpartumCard({required this.birthDate, required this.today, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final until = daysUntilCheck(daysSinceBirth(birthDate, today));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Palette.violet.withValues(alpha: 0.14), Palette.rose.withValues(alpha: 0.06)],
            ),
            border: Border.all(color: Palette.violet.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Palette.violet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.spa_outlined, color: Palette.violet, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('pp_card_title'),
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      until != null ? l.t('pp_check_in', {'n': until}) : l.t('pp_card_sub'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, fontWeight: FontWeight.w600),
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

class _BabySizeCard extends StatelessWidget {
  final int week;
  const _BabySizeCard({required this.week});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final size = babySizeFor(week);
    if (size == null) return const SizedBox.shrink();
    final cm = size.lengthCm % 1 == 0 ? size.lengthCm.toStringAsFixed(0) : size.lengthCm.toStringAsFixed(1);
    final highlight = fetalHighlightFor(week);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.rose.withValues(alpha: 0.14), Palette.violet.withValues(alpha: 0.05)],
        ),
        border: Border.all(color: Palette.rose.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The growing size disc, not a fixed icon: on the main view too,
              // the picture should show how big baby is this week, against
              // newborn size.
              BabySizeDisc(fraction: sizeVisualFraction(size.lengthCm), colour: Palette.roseDeep, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('bsize_title').toUpperCase(),
                        style: const TextStyle(color: Palette.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    const SizedBox(height: 3),
                    Text(l.t('bsize_about', {'food': l.t(size.code)}),
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Palette.text, height: 1.2)),
                    const SizedBox(height: 2),
                    Text(l.t('bsize_length', {'cm': cm}),
                        style: const TextStyle(color: Palette.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          // "Baby this week" — the same development highlight the week-detail
          // screen shows, brought onto the overview so the wonder of the week is
          // here too, not a tap away.
          if (highlight != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: Palette.border),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 17, color: Palette.roseDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l.t('fet_${highlight.id}'),
                      style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ],
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
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('gest_milestones').toUpperCase(),
              style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 12),
          _MilestoneRow(
            icon: Icons.flag_rounded,
            color: Palette.violet,
            label: l.t(current.code),
            badge: l.t('ms_now'),
            badgeColor: Palette.violet,
          ),
          if (next != null) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Palette.border)),
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
              style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
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
                style: const TextStyle(color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w600)),
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
  const _KickHistory({required this.sessions, required this.today, required this.onClear, required this.onOpenAll});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final shown = sessions.take(5).toList();
    final summary = kickHistorySummary(sessions);
    return GlassCard(
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
            if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Palette.border)),
            _KickHistoryRow(record: shown[i], now: today),
          ],
          if (sessions.length > shown.length) _SeeAllRow(count: sessions.length, onTap: onOpenAll),
        ],
      ),
    );
  }
}

/// A generic full-history screen: a titled list of pre-built rows.
class SessionHistoryScreen extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const SessionHistoryScreen({super.key, required this.title, required this.rows});

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
          itemBuilder: (_, i) => GlassCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: rows[i]),
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
                  style: const TextStyle(color: Palette.violetText, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 18, color: Palette.violet),
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
        color: Palette.violet.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _KickSummaryStat(value: summary.avgCount.toStringAsFixed(summary.avgCount % 1 == 0 ? 0 : 1), label: l.t('kick_avg_count')),
          _kickDivider(),
          _KickSummaryStat(value: formatElapsed(summary.avgDuration), label: l.t('kick_avg_length')),
          _kickDivider(),
          _KickSummaryStat(value: '${summary.goalReached}/${summary.sessions}', label: l.t('kick_goal_hits')),
        ],
      ),
    );
  }

  Widget _kickDivider() => Container(width: 1, height: 30, color: Palette.border);
}

class _KickSummaryStat extends StatelessWidget {
  final String value;
  final String label;
  const _KickSummaryStat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 18, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, fontSize: 11)),
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
    final reached = kickGoalReached(record.count, defaultKickGoal);
    return Row(
      children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(gradient: Palette.roseViolet, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.child_care_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('kick_history_count', {'n': record.count}),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${formatElapsed(record.duration)} · ${l.ago(age.isNegative ? Duration.zero : age)}',
                  style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
            ],
          ),
        ),
        if (reached)
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(color: Palette.good.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 16, color: Palette.good),
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
  const _ContractionHistory({required this.sessions, required this.today, required this.onClear, required this.onOpenAll});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final shown = sessions.take(5).toList();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HistoryHeader(title: l.t('contr_history'), onClear: onClear),
          const SizedBox(height: 12),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Palette.border)),
            _ContractionHistoryRow(record: shown[i], now: today),
          ],
          if (sessions.length > shown.length) _SeeAllRow(count: sessions.length, onTap: onOpenAll),
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
    final interval = record.avgIntervalSec > 0 ? formatElapsed(record.avgInterval) : '—';
    return Row(
      children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: Palette.violet.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.timer_outlined, size: 18, color: Palette.violet),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('contr_history_count', {'n': record.count}),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${l.t('contr_history_interval', {'i': interval})} · ${l.ago(age.isNegative ? Duration.zero : age)}',
                  style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
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
  const _MilestoneRow({required this.icon, required this.color, required this.label, required this.badge, required this.badgeColor});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
          child: Text(badge, style: TextStyle(color: darkenForText(badgeColor), fontWeight: FontWeight.w700, fontSize: 12)),
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
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.display, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(display, style: const TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: Palette.roseDeep)),
        ]),
        Slider(
          value: value, min: min, max: max, divisions: (max - min).round(),
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
      CyclePhase.menstrual => (l.t('phase_menstrual'), Palette.roseDeep, Icons.water_drop_rounded),
      CyclePhase.follicular => (l.t('phase_follicular'), Palette.violet, Icons.eco_rounded),
      CyclePhase.fertile => (l.t('phase_fertile'), Palette.teal, Icons.brightness_high_rounded),
      CyclePhase.luteal => (l.t('phase_luteal'), Palette.amber, Icons.nightlight_round),
    };
    final note = l.t('phase_${phase.phase.name}_note');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: color)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                      child: Text(l.t('phase_day', {'n': phase.dayInPhase, 'of': phase.phaseLength}),
                          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(note, style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.35)),
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
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: Palette.amber.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.lightbulb_outline_rounded, color: Palette.amber, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('cyc_usual_title'),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Palette.text)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: [
                    for (final s in top)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Palette.amber.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Palette.amber.withValues(alpha: 0.25)),
                        ),
                        child: Text('${l.t('sym_${s.symptom.name}')} · ${s.count}×',
                            style: const TextStyle(color: Palette.text, fontSize: 12, fontWeight: FontWeight.w600)),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.teal.withValues(alpha: 0.12), Palette.teal.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: Palette.teal.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: Palette.teal.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.eco_rounded, color: Palette.teal, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('cyc_fertile_in', {'n': countdown.daysToStart}),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.teal, height: 1.2)),
                const SizedBox(height: 3),
                Text(l.t('cyc_ovulation_in', {'n': countdown.daysToOvulation}),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
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
  const _CyclePredictions({required this.info, required this.confidence});

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

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('cyc_predictions').toUpperCase(),
              style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
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
            value: '${ml.formatMediumDate(info.fertileStart!)} – ${ml.formatMediumDate(info.fertileEnd!)}',
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
                child: Text(l.t('cyc_avg_cycle', {'n': info.avgCycleLength}),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12)),
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
      PredictionConfidence.building => (Palette.amber, l.t('cyc_conf_building')),
      // Amber like 'building' — the date is equally approximate — but the
      // words say why, and that logging more will not sharpen it.
      PredictionConfidence.variable => (Palette.amber, l.t('cyc_conf_variable')),
      PredictionConfidence.good => (Palette.good, l.t('cyc_conf_good')),
    };
    return Tooltip(
      message: l.t('cyc_conf_tip'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insights_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
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
  const _PredRow({required this.icon, required this.color, required this.label, required this.value, this.badge, this.badgeColor});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
              const SizedBox(height: 1),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: badgeColor!.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(badge!, style: TextStyle(color: badgeColor, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
      ],
    );
  }
}

class _PredDivider extends StatelessWidget {
  const _PredDivider();
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Palette.border));
}

/// Legend for the cycle calendar colours.
class _CycleLegend extends StatelessWidget {
  const _CycleLegend();
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Wrap(
      spacing: 16, runSpacing: 8,
      children: [
        _LegendDot(color: Palette.roseDeep, label: l.t('cyc_period')),
        _LegendDot(color: Palette.rose.withValues(alpha: 0.5), label: l.t('cyc_predicted')),
        _LegendDot(color: Palette.teal.withValues(alpha: 0.5), label: l.t('cyc_fertile')),
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
      Container(width: 11, height: 11, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
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
  const _BirthNameDialog({required this.title, required this.label, required this.save});

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
