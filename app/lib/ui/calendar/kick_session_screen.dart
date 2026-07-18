/// KickSessionScreen — a focused, timed fetal-movement counter. A big central
/// tap target logs each movement; a live clock (started on the first tap) shows
/// how long the session has run. On save, the session's movements are added to
/// the day's log. NON-medical: it only counts + times, with no targets or advice.
///
/// State/timing lives here; the counting + elapsed logic is the pure
/// [KickSession] model (verified by verify_kicks.dart).
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../domain/kick_session.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';

class KickSessionScreen extends StatefulWidget {
  /// Called with the number of movements and how long the session ran, on save.
  final void Function(int count, Duration elapsed) onSave;
  const KickSessionScreen({super.key, required this.onSave});

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
    setState(() => _session = _session.tap(DateTime.now()));
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
    widget.onSave(_session.count, _session.elapsed(DateTime.now()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.t('kick_session_saved', {'n': _session.count})),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
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
    final elapsed = formatElapsed(_session.elapsed(DateTime.now()));

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
                  return Semantics(
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
                            gradient: reached
                                ? const LinearGradient(colors: [Palette.good, Palette.teal])
                                : Palette.roseViolet,
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
                                  gradient: reached
                                      ? const LinearGradient(colors: [Palette.good, Palette.teal])
                                      : Palette.roseViolet,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (reached ? Palette.good : Palette.rose).withValues(alpha: 0.40),
                                      blurRadius: 40,
                                      spreadRadius: -8,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
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
                                      l.t(reached ? 'kick_goal_reached' : 'kick_session_tap'),
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
