/// Screen 22 — «Ночь · кормление». A NIGHT screen.
///
/// docs/CLAUDE-app-design.md: «Заголовок + «тихие часы» → таймер 12:38 +
/// Пауза/Закончить → две карточки (прошлое кормление / за сутки) → три кнопки
/// (Подгузник, Сон, Заметка) → пояснение про одну руку в темноте.»
///
/// The newborn log could record that a feed happened. It could not time one —
/// and at 4am the question is not «did I feed her» but «how long has she been
/// on this side», which is the number a mother is trying to hold in her head
/// while half asleep.
///
/// Every rule of §2.17 is load-bearing here, and the last one most of all:
/// «крупные цифры, действие в нижней трети, вибрация вместо звука». She is
/// holding a baby with one arm. The controls have to be reachable with a thumb,
/// large enough to hit without looking, and must not make a sound.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../domain/newborn_log.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';

class NightFeedScreen extends StatefulWidget {
  final String childName;

  /// Everything logged so far, for the two summary cards.
  final List<NewbornEvent> events;
  final void Function(NewbornEvent event) onLog;

  /// Injected so the summaries are testable against a fixed clock.
  final DateTime Function() now;

  const NightFeedScreen({
    super.key,
    required this.childName,
    required this.events,
    required this.onLog,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  State<NightFeedScreen> createState() => _NightFeedScreenState();
}

class _NightFeedScreenState extends State<NightFeedScreen> {
  Timer? _ticker;

  /// Total time on this feed, excluding pauses.
  Duration _elapsed = Duration.zero;

  /// When the running segment began. Null while paused or not started.
  DateTime? _segmentStart;

  bool get _running => _segmentStart != null;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration get _shown {
    final start = _segmentStart;
    if (start == null) return _elapsed;
    return _elapsed + widget.now().difference(start);
  }

  void _startOrPause() {
    // Haptic, never a sound: «вибрация вместо звука». A chime at 4am wakes the
    // baby she has just got back to sleep, which is the opposite of helping.
    HapticFeedback.mediumImpact();
    setState(() {
      if (_running) {
        _elapsed += widget.now().difference(_segmentStart!);
        _segmentStart = null;
        _ticker?.cancel();
      } else {
        _segmentStart = widget.now();
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      }
    });
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    _ticker?.cancel();
    final total = _shown;
    // Under a minute is a mis-tap, not a feed. Recording it would put noise
    // into the very averages the day screen reads.
    if (total.inMinutes >= 1) {
      widget.onLog(NewbornEvent(
        at: widget.now(),
        kind: NewbornEventKind.feed,
        durationMin: total.inMinutes,
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _quickLog(NewbornEventKind kind) {
    HapticFeedback.selectionClick();
    widget.onLog(NewbornEvent(at: widget.now(), kind: kind));
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final now = widget.now();
    final last = lastOfKind(widget.events, NewbornEventKind.feed);
    final today = summaryFor(widget.events, now);

    return Scaffold(
      backgroundColor: Ds.nightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Ds.nightText,
        // The theme sets titleTextStyle explicitly, so foregroundColor alone
        // does not reach the title.
        title: Text(l.t('nightfeed_title'),
            style: const TextStyle(color: Ds.nightText)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.t('nightfeed_quiet_hours'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Ds.nightTextDim, fontSize: 13, height: 1.4)),
              const SizedBox(height: 14),

              // «крупные цифры» — 52px, readable at arm's length in the dark.
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Ds.nightSurface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Text(
                      _running
                          ? l.t('nightfeed_feeding')
                          : (_shown == Duration.zero
                              ? l.t('nightfeed_ready')
                              : l.t('nightfeed_paused')),
                      style: const TextStyle(fontSize: 13, color: Ds.nightTextDim),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _mmss(_shown),
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                        fontSize: 52,
                        letterSpacing: -1.04, // -.02em
                        height: 1.1,
                        color: Ds.nightText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Row(children: [
                Expanded(
                  child: _NightCard(
                    label: l.t('nightfeed_last'),
                    value: last == null
                        ? l.t('nightfeed_none_yet')
                        : l.t('nightfeed_ago', {'n': now.difference(last.at).inMinutes}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NightCard(
                    label: l.t('nightfeed_today'),
                    value: l.t('nightfeed_count', {'n': today.feeds}),
                  ),
                ),
              ]),

              // «действие в нижней трети» — everything above is information;
              // everything she presses is down here, under her thumb.
              const Spacer(),

              Row(children: [
                Expanded(
                  child: _QuickButton(
                    label: l.t('nb_diaper'),
                    onTap: () => _quickLog(NewbornEventKind.diaper),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickButton(
                    label: l.t('nb_sleep'),
                    onTap: () => _quickLog(NewbornEventKind.sleep),
                  ),
                ),
              ]),
              const SizedBox(height: 10),

              if (_shown > Duration.zero) ...[
                _NightAction(
                  label: _running ? l.t('nightfeed_pause') : l.t('nightfeed_resume'),
                  filled: false,
                  onTap: _startOrPause,
                ),
                const SizedBox(height: 10),
                _NightAction(label: l.t('nightfeed_finish'), onTap: _finish),
              ] else
                _NightAction(label: l.t('nightfeed_start'), onTap: _startOrPause),

              const SizedBox(height: 10),
              Text(l.t('nightfeed_one_hand'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Ds.nightTextDim, fontSize: 12, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NightCard extends StatelessWidget {
  final String label;
  final String value;
  const _NightCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Ds.nightSurface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Ds.nightTextDim)),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: Ds.nightText)),
          ],
        ),
      );
}

/// A secondary control — logging a nappy without leaving the timer.
class _QuickButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Ds.nightSurface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Ds.nightText)),
          ),
        ),
      );
}

/// The one big action. 96dp minimum — «действие в нижней трети», hit without
/// looking, with a baby in the other arm.
class _NightAction extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _NightAction({required this.label, this.filled = true, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: filled ? 96 : 60),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? Ds.nightAction : Ds.nightSurface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: filled ? 22 : 16,
                color: filled ? Ds.nightActionText : Ds.nightText,
              ),
            ),
          ),
        ),
      );
}
