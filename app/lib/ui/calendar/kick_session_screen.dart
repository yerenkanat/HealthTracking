/// KickSessionScreen — a focused, timed fetal-movement counter. A big central
/// tap target logs each movement; a live clock (started on the first tap) shows
/// how long the session has run. On save, the session's movements are added to
/// the day's log.
///
/// It counts against the count-to-ten method — ten movements in about two hours
/// — and on save it says which of the three things happened. The claim that it
/// was "NON-medical, with no targets or advice" was never true (the goal and
/// the window are right there in [KickSession]), and it was the cover under
/// which the not-reached branch went missing: a slow-but-reached session got a
/// sentence, four movements in an hour got «Записано шевелений: 4» and nothing.
///
/// Now: two hours with fewer than ten movements — the method's own trigger —
/// shows the app's movement guidance, what to do today, and the route to the
/// warning-signs screen. A session ended BEFORE the window gets only a neutral
/// note of what the method looks for: the method has given no signal there, and
/// firing the escalation copy every casual session would teach her to dismiss
/// it. Ten felt slowly keeps its existing `kick_goal_reached_slow` line. It
/// still diagnoses nothing.
///
/// State/timing lives here; the counting + elapsed logic is the pure
/// [KickSession] model (verified by verify_kicks.dart).
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../domain/kick_session.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';
import 'pregnancy_warnings.dart';

class KickSessionScreen extends StatefulWidget {
  /// Called with the number of movements and how long the session ran, on save.
  final void Function(int count, Duration elapsed) onSave;

  /// The clock. Injectable so a test can reach the two-hour branch — the one
  /// that carries the medical copy — without waiting two hours for it.
  final DateTime Function() clock;

  const KickSessionScreen({super.key, required this.onSave, this.clock = DateTime.now});

  @override
  State<KickSessionScreen> createState() => _KickSessionScreenState();
}

class _KickSessionScreenState extends State<KickSessionScreen> {
  KickSession _session = const KickSession();
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tap() {
    HapticFeedback.mediumImpact();
    setState(() => _session = _session.tap(widget.clock()));
    // Start the once-a-second repaint only after the first movement.
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _undo() {
    HapticFeedback.selectionClick();
    setState(() => _session = _session.undo());
    if (!_session.started) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _close() async {
    final l = L10nScope.of(context);
    if (_session.count == 0) {
      Navigator.of(context).pop();
      return;
    }
    // Save the session — it added real data, so leaving needs no destructive prompt.
    final count = _session.count;
    final elapsed = _session.elapsed(widget.clock());
    widget.onSave(count, elapsed);
    if (!mounted) return;
    // Two hours passed and ten movements did not arrive — the method's own
    // trigger. The count alone («Записано шевелений: 4») is the fact she cannot
    // act on; what to do about it, and the way to the warning signs, is.
    if (kickSessionNeedsGuidance(count, elapsed)) {
      await _showMovementGuidance(count, elapsed);
      if (!mounted) return;
    }
    // She stopped before the window was up: the method has said nothing, so
    // neither does the app beyond what it looks for. A neutral line beside the
    // save — no dialog, no clinic instruction, nothing to dismiss.
    final early = kickSessionEndedEarly(count, elapsed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: early
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('kick_session_saved', {'n': count})),
                  const SizedBox(height: 4),
                  Text(
                    l.t('kick_method_note'),
                    style: const TextStyle(fontSize: 12.5, height: 1.35),
                  ),
                ],
              )
            : Text(l.t('kick_session_saved', {'n': count})),
        duration: early ? const Duration(seconds: 6) : const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }

  /// The trigger branch (two hours, fewer than ten): her numbers, what the
  /// method looks for, what to do about it today, and the clinic sentence —
  /// with one tap to the full warning-signs screen (which carries «Малыш
  /// шевелится заметно меньше обычного» and the ambulance number). Diagnoses
  /// nothing, invents no threshold, blocks nothing.
  Future<void> _showMovementGuidance(int count, Duration elapsed) async {
    final l = L10nScope.of(context);
    final openWarnings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.favorite_border_rounded, size: 20, color: Palette.roseDeep),
            const SizedBox(width: 8),
            Expanded(child: Text(l.t('kick_low_title'))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.t('kick_low_body', {'n': count, 't': formatElapsed(elapsed)}),
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              // The action the method attaches to its own threshold — the app
              // used to teach the numbers and stop, so six movements in two
              // hours met the trigger for calling and she was never told.
              Text(
                l.t('kick_low_action'),
                style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              // …and the other trigger, unchanged: movements noticeably fewer
              // than usual, at any hour.
              Text(
                l.t('preg_note_movement_pattern'),
                style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('act_close')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('preg_warn_title'),
                style: const TextStyle(color: Palette.roseDeep, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (openWarnings != true || !mounted) return;
    // Pushed ON TOP of this screen, not instead of it: she comes back here and
    // the save then completes as usual.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PregnancyWarningsScreen()),
    );
  }

  Future<bool> _confirmDiscard() async {
    final l = L10nScope.of(context);
    if (_session.count == 0) return true;
    return confirmDestructive(
      context,
      title: l.t('kick_session_discard_title'),
      message: l.t('kick_session_discard_body'),
      confirmLabel: l.t('kick_session_discard'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final elapsed = formatElapsed(_session.elapsed(widget.clock()));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Palette.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(l.t('kick_session_title')),
          leading: IconButton(
            tooltip: l.t('act_cancel'),
            icon: const Icon(Icons.close_rounded, color: Palette.textDim),
            onPressed: () async {
              if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
            },
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                // Live clock.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.timer_outlined, size: 18, color: Palette.textDim),
                    const SizedBox(width: 6),
                    Text(
                      elapsed,
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Palette.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _session.started ? l.t('kick_session_running') : l.t('kick_session_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.textDim, fontSize: 13, height: 1.35),
                ),
                const Spacer(),
                // Big central tap target, ringed with progress toward the goal.
                Builder(builder: (context) {
                  final reached = kickGoalReached(_session.count, defaultKickGoal);
                  // Reached WITHIN the two-hour reference window. Ten
                  // movements felt over three hours used to show the same
                  // "Goal reached {1F389}" as ten in twenty minutes 2014 confetti at the
                  // exact moment the count-to-ten method exists to notice.
                  final prompt = kickGoalReachedPromptly(
                      _session.count, _session.elapsed(widget.clock()));
                  // MergeSemantics, or the InkWell inside publishes its OWN
                  // unlabelled node beside this labelled one — a screen reader
                  // then finds a bare "button" on the screen whose entire
                  // purpose is that one control. The label here was always
                  // right; it just was not reaching the node that gets tapped.
                  return MergeSemantics(
                    child: Semantics(
                    button: true,
                    label: l.t('kick_add'),
                    value: '${_session.count} / $defaultKickGoal',
                    child: SizedBox(
                      width: 244,
                      height: 244,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          MetricRing(
                            fraction: kickGoalFraction(_session.count, defaultKickGoal),
                            color: reached ? Palette.good : Ds.coralCta,
                            size: 244,
                            stroke: 8,
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _tap,
                              customBorder: const CircleBorder(),
                              child: Container(
                                width: 206,
                                height: 206,
                                decoration: BoxDecoration(
                                  color: reached ? Palette.good : Ds.coralCta,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Ds.ink,
                                      width: DsShape.borderWidth),
                                  boxShadow: DsShape.hardShadowLg,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text(
                                              '${_session.count}',
                                              style: const TextStyle(
                                                fontFamily: 'JetBrainsMono', fontSize: 68, fontWeight: FontWeight.w700, height: 1, color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              ' / $defaultKickGoal',
                                              style: TextStyle(
                                                fontFamily: 'JetBrainsMono', fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l.t(reached
                                          ? (prompt ? 'kick_goal_reached' : 'kick_goal_reached_slow')
                                          : 'kick_session_tap'),
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  );
                }),
                const SizedBox(height: 18),
                TextButton.icon(
                  onPressed: _session.count == 0 ? null : _undo,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text(l.t('kick_session_undo')),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _close,
                    style: FilledButton.styleFrom(
                      backgroundColor: Palette.violet,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: Text(
                      _session.count == 0 ? l.t('kick_session_close') : l.t('kick_session_save'),
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
