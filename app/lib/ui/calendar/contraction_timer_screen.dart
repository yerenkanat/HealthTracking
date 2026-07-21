/// ContractionTimerScreen — a live labour companion. One big button toggles a
/// contraction on/off: tap to start when one begins, tap again when it ends. Each
/// contraction is timed, and the gap between consecutive starts (the interval) is
/// shown, with running averages up top. In-session only (not persisted) — this is
/// a live tool. NON-medical: it measures, it doesn't advise.
///
/// The counting/averages are the pure [contraction] domain; timing lives here.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../domain/contraction.dart';
import '../../domain/kick_session.dart' show formatElapsed;
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';

class ContractionTimerScreen extends StatefulWidget {
  /// Called with the session summary when the screen closes (if any contractions
  /// were recorded), so it can be added to history.
  final void Function(int count, Duration avgDuration, Duration avgInterval)? onSave;
  const ContractionTimerScreen({super.key, this.onSave});
  @override
  State<ContractionTimerScreen> createState() => _ContractionTimerScreenState();
}

class _ContractionTimerScreenState extends State<ContractionTimerScreen> {
  final List<Contraction> _contractions = []; // earliest-first
  DateTime? _activeStart; // set while a contraction is in progress
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    // Persist the session on the way out (reset clears the list, so a reset
    // session won't be saved).
    if (_contractions.isNotEmpty) {
      final s = contractionStats(_contractions);
      widget.onSave?.call(s.count, s.avgDuration, s.avgInterval);
    }
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.mediumImpact();
    final now = DateTime.now();
    setState(() {
      if (_activeStart == null) {
        _activeStart = now;
        _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      } else {
        _contractions.add(Contraction(start: _activeStart!, end: now));
        _activeStart = null;
        _ticker?.cancel();
        _ticker = null;
      }
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
    final elapsed = active ? formatElapsed(DateTime.now().difference(_activeStart!)) : '0:00';

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(l.t('contr_title')),
        actions: [
          if (_contractions.isNotEmpty || active)
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded, color: Palette.textDim),
              tooltip: l.t('contr_reset'),
              onPressed: _reset,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_contractions.isNotEmpty) _StatsBar(stats: stats),
            // The clock is passed so the window is the last hour of HER time,
            // not the last hour of recorded contractions. Without it, a pattern
            // that stopped two hours ago would go on claiming to be met — and
            // contractions that faded are exactly when she should not be told
            // to set off for hospital.
            if (_contractions.length >= 2)
              _FiveOneOneCard(
                progress: fiveOneOneProgress(_contractions, now: DateTime.now()),
              ),
            const SizedBox(height: 8),
            _BigButton(active: active, elapsed: elapsed, label: l.t(active ? 'contr_stop' : 'contr_start'), sub: l.t(active ? 'contr_running' : 'contr_hint'), onTap: _toggle),
            const SizedBox(height: 12),
            Expanded(
              child: _contractions.isEmpty
                  ? Center(child: Text(l.t('contr_empty'), textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: _contractions.length,
                      itemBuilder: (context, i) {
                        // Newest first.
                        final idx = _contractions.length - 1 - i;
                        final c = _contractions[idx];
                        final interval = intervalBefore(_contractions, idx);
                        return _ContractionRow(
                          number: idx + 1,
                          duration: c.duration,
                          interval: interval,
                          l: l,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final ContractionStats stats;
  const _StatsBar({required this.stats});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            _Stat(value: '${stats.count}', label: l.t('contr_count')),
            _divider(),
            _Stat(value: formatElapsed(stats.avgDuration), label: l.t('contr_avg_dur')),
            _divider(),
            _Stat(value: stats.avgInterval == Duration.zero ? '—' : formatElapsed(stats.avgInterval), label: l.t('contr_avg_freq')),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 34, color: Palette.border);
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
    final accent = progress.allMet ? Palette.roseDeep : Palette.violet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: accent.withValues(alpha: 0.07),
          border: Border.all(color: accent.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(progress.allMet ? Icons.info_rounded : Icons.timeline_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.t('contr_511_title'),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: accent)),
                ),
                Text('${progress.metCount}/3', style: TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: accent, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            _Criterion(met: progress.intervalMet, label: l.t('contr_511_interval')),
            _Criterion(met: progress.durationMet, label: l.t('contr_511_duration')),
            _Criterion(met: progress.sustainedMet, label: l.t('contr_511_sustained')),
            const SizedBox(height: 8),
            Text(progress.allMet ? l.t('contr_511_ready') : l.t('contr_511_note'),
                style: const TextStyle(color: Palette.textDim, fontSize: 11.5, height: 1.35)),
          ],
        ),
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
        children: [
          Icon(met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 18, color: met ? Palette.good : Palette.textDim.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13.5, color: met ? Palette.text : Palette.textDim, fontWeight: met ? FontWeight.w600 : FontWeight.w400)),
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
            Text(value, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, fontSize: 11.5)),
          ],
        ),
      );
}

class _BigButton extends StatelessWidget {
  final bool active;
  final String elapsed;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _BigButton({required this.active, required this.elapsed, required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gradient = active
        ? const LinearGradient(colors: [Palette.roseDeep, Palette.rose])
        : const LinearGradient(colors: [Palette.violet, Palette.pink]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: label,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 180, height: 180,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: (active ? Palette.roseDeep : Palette.violet).withValues(alpha: 0.4), blurRadius: 36, spreadRadius: -6, offset: const Offset(0, 12))],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(active ? elapsed : label,
                          style: TextStyle(fontFamily: active ? 'JetBrainsMono' : null, fontSize: active ? 40 : 26, fontWeight: FontWeight.w700, color: Colors.white)),
                      if (active) ...[
                        const SizedBox(height: 4),
                        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ContractionRow extends StatelessWidget {
  final int number;
  final Duration duration;
  final Duration? interval;
  final L10n l;
  const _ContractionRow({required this.number, required this.duration, required this.interval, required this.l});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(color: Palette.violet.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.violet)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l.t('contr_duration', {'d': formatElapsed(duration)}),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.text)),
            ),
            Text(interval == null ? l.t('contr_first') : l.t('contr_apart', {'i': formatElapsed(interval!)}),
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
