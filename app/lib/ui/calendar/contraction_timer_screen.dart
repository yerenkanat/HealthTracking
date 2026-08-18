/// ContractionTimerScreen — screen 10 of `docs/CLAUDE-app-design.md`, and the
/// only NIGHT screen in the calendar module.
///
/// The frame it is built to, quoted whole:
///
///   «10 · Таймер схваток — НОЧНАЯ. "‹ Схватки / История" → карточка таймера
///    0:47 + интервал → плашка #45162A "по минуте каждые 5 минут в течение
///    часа — пора в роддом" → список последних схваток → крупная кнопка
///    "Схватка закончилась" → подпись "экран не гаснет".»
///
/// …and ЧАСТЬ 4 rule 8: «Ночь — крупные цифры, действие в нижней трети,
/// вибрация.»
///
/// THE ONE THING THIS SCREEN DOES NOT BUILD, AND WHY
///
/// The `#45162A` plate. Its text is a medical instruction — it tells a woman in
/// labour when to leave her house — and no clinical gate has ruled on it. The
/// card is built and wired; its copy key is null. See `domain/labour_alert.dart`
/// for the whole argument and for the three things a verdict has to produce.
/// What ships in its place is the 5-1-1 CHECKLIST, which describes her own
/// timings back to her and instructs nothing.
///
/// One big button toggles a contraction on/off. Each contraction is timed, and
/// the gap between consecutive STARTS (the interval) is what labour is measured
/// by. In-session only — this is a live tool; the summary is handed to [onSave]
/// on the way out and lands in the calendar's history.
///
/// The counting/averages are the pure [contraction] domain; timing lives here.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../domain/contraction.dart';
import '../../domain/kick_session.dart' show formatElapsed;
import '../../domain/labour_alert.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../widgets/confirm.dart';
import '../ds_widgets.dart';
import 'labour_signs_screen.dart';

/// Hold the screen on, or let it sleep again. Injected so a widget test can
/// assert the screen asks — the real one talks to the platform.
typedef KeepAwake = Future<void> Function(bool on);

/// Ask the platform, and carry on if it refuses.
///
/// A wakelock is a convenience; the timer is the point. If the platform channel
/// is missing — an OS that declines it, a widget test with no plugins — the
/// screen must still count contractions. Letting this throw would crash the one
/// screen a woman is holding during labour, to avoid the lesser problem of the
/// display dimming.
Future<void> _defaultKeepAwake(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (_) {
    // Deliberately swallowed. Nothing the user could do about it, and nothing
    // worth interrupting her for.
  }
}

/// Wall-clock `HH:mm`, zero-padded, ours and numeric.
///
/// NOT `MaterialLocalizations.formatTimeOfDay`, which renders «3:41 AM» under a
/// locale this app does not always hand it — and the hospital asks her what
/// time the contractions started, so this number gets read down a telephone.
String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class ContractionTimerScreen extends StatefulWidget {
  /// Called with the session summary when the screen closes (if any contractions
  /// were recorded), so it can be added to history.
  final void Function(int count, Duration avgDuration, Duration avgInterval)?
      onSave;

  /// Opens the saved-session history — the «История» action of frame 10.
  ///
  /// Optional, and the action does not render without it. The history lives on
  /// the calendar screen, which owns the records; a timer opened without one
  /// draws no dead control rather than a button that does nothing.
  final VoidCallback? onOpenHistory;

  /// «Экран не гаснет». A phone that sleeps mid-labour loses the interval she
  /// is timing, and she is in no position to keep tapping it awake — the whole
  /// value of this screen is the gap between contractions, which is exactly
  /// what a screen timeout destroys.
  final KeepAwake keepAwake;

  const ContractionTimerScreen({
    super.key,
    this.onSave,
    this.onOpenHistory,
    this.keepAwake = _defaultKeepAwake,
  });
  @override
  State<ContractionTimerScreen> createState() => _ContractionTimerScreenState();
}

class _ContractionTimerScreenState extends State<ContractionTimerScreen> {
  final List<Contraction> _contractions = []; // earliest-first
  DateTime? _activeStart; // set while a contraction is in progress
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.keepAwake(true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Released on the way out, and NOT conditionally: leaving the wakelock on
    // because the session had no contractions would flatten the battery of a
    // phone she is relying on to call somebody.
    widget.keepAwake(false);
    // Persist the session on the way out (reset clears the list, so a reset
    // session won't be saved).
    if (_contractions.isNotEmpty) {
      final s = contractionStats(_contractions);
      widget.onSave?.call(s.count, s.avgDuration, s.avgInterval);
    }
    super.dispose();
  }

  /// One ticker for the whole session, not one per contraction.
  ///
  /// It used to run only while a contraction was in progress, because the only
  /// live number was the contraction's own length. The REST timer is live too —
  /// «Перерыв 4:20» counting up is the number she is actually watching, since
  /// the interval is what tells her labour is progressing — so the clock has to
  /// keep going between contractions as well.
  void _ensureTicking() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _toggle() {
    HapticFeedback.mediumImpact();
    final now = DateTime.now();
    setState(() {
      if (_activeStart == null) {
        _activeStart = now;
      } else {
        _contractions.add(Contraction(start: _activeStart!, end: now));
        _activeStart = null;
      }
      _ensureTicking();
    });
  }

  Future<void> _reset() async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('contr_reset_title'),
      message: l.t('contr_reset_body'),
      confirmLabel: l.t('contr_reset'),
    );
    if (!ok) return;
    setState(() {
      _contractions.clear();
      _activeStart = null;
      _ticker?.cancel();
      _ticker = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final active = _activeStart != null;
    final stats = contractionStats(_contractions);
    final now = DateTime.now();
    final hasAny = _contractions.isNotEmpty || active;

    // The clock is passed so the window is the last hour of HER time, not the
    // last hour of recorded contractions. Without it, a pattern that stopped two
    // hours ago would go on claiming to be met — and contractions that faded are
    // exactly when she should not be told to set off for hospital.
    final progress = fiveOneOneProgress(_contractions, now: now);

    return Scaffold(
      backgroundColor: Ds.nightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        // The theme sets titleTextStyle explicitly, so foregroundColor alone
        // does not reach the title — it stayed ink on the night canvas at
        // 1.08:1, which the accessibility sweep caught.
        title: Text(l.t('contr_title'),
            style: const TextStyle(color: Ds.nightText)),
        iconTheme: const IconThemeData(color: Ds.nightText),
        actions: [
          // "Am I in labour / should I go in?" — the question this screen exists
          // to help answer, one tap away, and the only route to it from here.
          IconButton(
            icon:
                const Icon(Icons.info_outline_rounded, color: Ds.nightTextDim),
            tooltip: l.t('lab_title'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LabourSignsScreen()),
            ),
          ),
          // «История» — a TEXT action, as frame 10 draws it. Reset is NOT up
          // here: it used to be, next to navigation, where a thumb going for
          // history could land on the control that erases the session. It now
          // sits on the list header, beside the thing it destroys.
          if (widget.onOpenHistory != null)
            TextButton(
              onPressed: widget.onOpenHistory,
              child: Text(l.t('contr_history_short'),
                  style: const TextStyle(
                      color: Ds.nightAction, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // A ListView and not a Column: at 130 % text scale in Kazakh the
              // live card, the 5-1-1 card and the stats bar together are taller
              // than a 320dp phone, and a fixed Column paints the barber pole
              // over the timer.
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  // 1 · HEADLINE. What is happening right now, in the biggest
                  // digits on the screen (§2.17: «крупные цифры»).
                  if (hasAny)
                    _LiveCard(
                      activeStart: _activeStart,
                      contractions: _contractions,
                      now: now,
                    ),
                  // 2 · The gate-pending «пора в роддом» plate. Renders NOTHING
                  // until the clinical gate rules — see domain/labour_alert.dart.
                  _LabourAlertCard(progress: progress),
                  // 3 · The pattern read: three criteria, ticked from her own
                  // timings, instructing nothing.
                  if (_contractions.length >= 2) ...[
                    const SizedBox(height: 12),
                    _FiveOneOneCard(progress: progress),
                  ],
                  // 4 · The numbers a triage nurse asks for down the phone:
                  // how many, how long, how far apart.
                  if (_contractions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StatsBar(stats: stats),
                    const SizedBox(height: 18),
                    _ListHeader(onReset: _reset),
                    const SizedBox(height: 8),
                    // 5 · The log, newest first — the order she reads it in.
                    // The ordering and the interval pairing are [contractionRows],
                    // pure and unit-tested, rather than index arithmetic inline.
                    for (final row in contractionRows(_contractions))
                      _ContractionRow(row: row, l: l),
                  ],
                  if (_contractions.isEmpty && !active)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(l.t('contr_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Ds.nightTextDim, height: 1.4)),
                    ),
                ],
              ),
            ),
            // Primary action in the thumb zone, in the shared bar rather than a
            // fourth hand-rolled one. Through labour she taps this over and over,
            // one-handed — a top-anchored button forces a phone re-grip each
            // time, so it lives at the bottom, under the resting thumb.
            DsBottomActionBar(
              fill: Ds.nightSurface,
              rule: Ds.nightTextDim,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DsPrimaryButton(
                    label: l.t(active ? 'contr_stop_big' : 'contr_start_big'),
                    fill: Ds.nightAction,
                    foreground: Ds.nightActionText,
                    onPressed: _toggle,
                  ),
                  const SizedBox(height: 8),
                  Text(l.t(active ? 'contr_stop_sub' : 'contr_hint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Ds.nightTextDim, fontSize: 13)),
                  const SizedBox(height: 6),
                  // «экран не гаснет». Both halves of this sentence are true and
                  // both are tested: the wakelock is taken in initState, and the
                  // canvas IS Ds.nightBg. It does NOT say the screen is dimmed —
                  // there is no brightness plugin in pubspec.yaml, and a promise
                  // the code does not keep is the defect this repo has spent the
                  // week clearing.
                  // FULL-STRENGTH nightTextDim, no alpha. At `alpha: 0.85` this
                  // blended toward the surface and measured 4.20:1 at 11.5px —
                  // the accessibility audit caught it. Undimmed it is 5.20:1 on
                  // Ds.nightSurface. The footnote is quiet because it is small
                  // and last, not because it is faded.
                  Text(l.t('contr_awake_note'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Ds.nightTextDim,
                          fontSize: 11.5,
                          height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The headline card of §2.17: a small dim label, then the running number at
/// 52px. Two states, because idle is the state this screen spends most of
/// labour in and a blank headline is a hole.
///
///   * a contraction is running → «Идёт схватка», its length, and the interval
///     from the previous contraction's start (the number labour is measured by);
///   * between contractions → «Перерыв», counting up from the last one's end,
///     and how long that last one lasted.
///
/// The interval line is OMITTED, not zeroed, for the first contraction of a
/// session: there is no previous start to measure from, and «интервал 0:00»
/// would be a measurement of something that was never measured.
class _LiveCard extends StatelessWidget {
  final DateTime? activeStart;
  final List<Contraction> contractions;
  final DateTime now;
  const _LiveCard(
      {required this.activeStart,
      required this.contractions,
      required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final active = activeStart != null;

    final String label;
    final Duration big;
    String? sub;

    if (active) {
      label = l.t('contr_live_active');
      big = now.difference(activeStart!);
      if (contractions.isNotEmpty) {
        final gap = activeStart!.difference(contractions.last.start);
        if (!gap.isNegative) {
          sub = l.t('contr_history_interval', {'i': formatElapsed(gap)});
        }
      }
    } else {
      label = l.t('contr_live_rest');
      final last = contractions.last;
      big = now.difference(last.end);
      sub = l.t('contr_duration', {'d': formatElapsed(last.duration)});
    }

    return DsCard(
      color: Ds.nightSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Ds.nightTextDim, fontSize: 13)),
          const SizedBox(height: 4),
          // «крупные цифры» — 52px, tabular so the digits do not jitter as the
          // seconds roll over.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(formatElapsed(big.isNegative ? Duration.zero : big),
                style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 52,
                    height: 1.05,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w700,
                    color: Ds.nightText)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Ds.nightTextDim, fontSize: 13.5)),
          ],
        ],
      ),
    );
  }
}

/// Frame 10's `#45162A` plate — BUILT, WIRED, AND SILENT.
///
/// [showLabourAlert] is false for every input while `labourAlertBodyKey` is
/// null, so this returns nothing at all today. When the clinical gate rules,
/// setting that one constant lights this up with no change here.
class _LabourAlertCard extends StatelessWidget {
  final FivOneOneProgress progress;
  const _LabourAlertCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    if (!showLabourAlert(progress)) return const SizedBox.shrink();
    final l = L10nScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DsCard(
        color: Ds.nightAlertBg,
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.local_hospital_rounded,
                size: 20, color: Ds.nightAction),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.t(labourAlertBodyKey!),
                  style: const TextStyle(
                      color: Ds.nightText,
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  final VoidCallback onReset;
  const _ListHeader({required this.onReset});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(l.t('contr_recent'),
              style: const TextStyle(
                  color: Ds.nightTextDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
        ),
        // Destructive, and it confirms — `confirmDestructive` names what goes.
        TextButton(
          onPressed: onReset,
          child: Text(l.t('contr_reset'),
              style: const TextStyle(color: Ds.nightTextDim, fontSize: 13)),
        ),
      ],
    );
  }
}

class _StatsBar extends StatelessWidget {
  final ContractionStats stats;
  const _StatsBar({required this.stats});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return DsCard(
      color: Ds.nightSurface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          _Stat(value: '${stats.count}', label: l.t('contr_count')),
          _divider(),
          _Stat(
              value: formatElapsed(stats.avgDuration),
              label: l.t('contr_avg_dur')),
          _divider(),
          // An em dash, not «0:00»: with one contraction there is no gap to
          // average, and a zero here would be a measured interval of nothing.
          _Stat(
              value: stats.avgInterval == Duration.zero
                  ? '—'
                  : formatElapsed(stats.avgInterval),
              label: l.t('contr_avg_freq')),
        ],
      ),
    );
  }

  Widget _divider() => Container(
      width: 1, height: 34, color: Ds.nightTextDim.withValues(alpha: 0.3));
}

/// Informational 5-1-1 progress: three criteria taught in childbirth classes,
/// each checked off as the timed pattern meets it. Always framed as a heads-up,
/// never a directive — the footer defers to the user's own provider.
class _FiveOneOneCard extends StatelessWidget {
  final FivOneOneProgress progress;
  const _FiveOneOneCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final accent = progress.allMet ? Ds.nightAction : Ds.nightTextDim;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: accent.withValues(alpha: 0.07),
        border: Border.all(
            color: Ds.nightTextDim.withValues(alpha: 0.25),
            width: DsShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  progress.allMet
                      ? Icons.info_rounded
                      : Icons.timeline_rounded,
                  size: 18,
                  color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.t('contr_511_title'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: accent)),
              ),
              Text('${progress.metCount}/3',
                  style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontWeight: FontWeight.w700,
                      color: accent,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          _Criterion(
              met: progress.intervalMet, label: l.t('contr_511_interval')),
          _Criterion(
              met: progress.durationMet, label: l.t('contr_511_duration')),
          _Criterion(
              met: progress.sustainedMet, label: l.t('contr_511_sustained')),
          const SizedBox(height: 8),
          Text(
              progress.allMet
                  ? l.t('contr_511_ready')
                  : l.t('contr_511_note'),
              style: const TextStyle(
                  color: Ds.nightTextDim, fontSize: 11.5, height: 1.35)),
        ],
      ),
    );
  }
}

class _Criterion extends StatelessWidget {
  final bool met;
  final String label;
  const _Criterion({required this.met, required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              met
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: met ? Ds.mint : Ds.nightTextDim.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    color: met ? Ds.nightText : Ds.nightTextDim,
                    fontWeight: met ? FontWeight.w600 : FontWeight.w400)),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Ds.nightText)),
            ),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Ds.nightTextDim, fontSize: 11.5)),
          ],
        ),
      );
}

/// One logged contraction: «03:41 · 0:58 · через 4:20».
///
/// The wall-clock START leads the row, not an ordinal. The number «7» is
/// derivable from the list and answers nothing; the time the contraction began
/// is what the maternity unit asks for on the phone, and what she needs when
/// she is trying to work out whether the last hour actually looked like an hour.
///
/// One duration format across the whole screen (`m:ss`), including the live
/// card's interval line. Frame 10's «4 мин 20 с» spelling was dropped
/// deliberately: two formats for one quantity on one screen is a reading cost
/// at 3am, and the spelled-out form would have needed a ninth unreviewed Kazakh
/// string to say something `4:20` already says.
class _ContractionRow extends StatelessWidget {
  final ContractionRow row;
  final L10n l;
  const _ContractionRow({required this.row, required this.l});

  @override
  Widget build(BuildContext context) {
    final interval = row.interval;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DsCard(
        color: Ds.nightSurface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Text(hhmm(row.start),
                style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ds.nightText)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(formatElapsed(row.duration),
                  style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 15,
                      color: Ds.nightText)),
            ),
            const SizedBox(width: 8),
            // The first contraction says «первая» rather than an interval:
            // there is no earlier start to measure the gap from.
            Flexible(
              child: Text(
                  interval == null
                      ? l.t('contr_first')
                      : l.t('contr_apart', {'i': formatElapsed(interval!)}),
                  textAlign: TextAlign.end,
                  style:
                      const TextStyle(color: Ds.nightTextDim, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
