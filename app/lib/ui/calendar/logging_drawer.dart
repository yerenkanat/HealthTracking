/// FloStyleCalendarDrawer — the animated bottom-sheet logging module. Big,
/// tappable pill buttons for dead-simple entry: mood, symptoms, and a fetal
/// kick counter with a large hit target. Stateless: it renders the passed
/// [DayLog] and calls back on every tap; the controller persists + re-emits,
/// and the sheet is rebuilt (via a StreamBuilder wrapper at the call site) so
/// selections light up instantly.
///
/// Deliverable component for the Women's Health calendar (Tab 2).
library;

import 'package:flutter/material.dart';
import '../../domain/cycle_log.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';

/// Icon + accent colour for each mood (localized label via `mood_<name>`).
({IconData icon, Color color}) _moodStyle(Mood m) => switch (m) {
      Mood.happy => (icon: Icons.sentiment_very_satisfied_rounded, color: Palette.good),
      Mood.calm => (icon: Icons.sentiment_satisfied_rounded, color: Palette.teal),
      Mood.anxious => (icon: Icons.sentiment_dissatisfied_rounded, color: Palette.amber),
      Mood.tired => (icon: Icons.bedtime_rounded, color: Palette.blue),
      Mood.sad => (icon: Icons.sentiment_very_dissatisfied_rounded, color: Palette.violet),
    };

/// Icon + accent colour for each symptom (localized label via `sym_<name>`).
({IconData icon, Color color}) _symptomStyle(Symptom s) => switch (s) {
      Symptom.allGood => (icon: Icons.auto_awesome_rounded, color: Palette.good),
      Symptom.cramps => (icon: Icons.bolt_rounded, color: Palette.amber),
      Symptom.spotting => (icon: Icons.water_drop_rounded, color: Palette.roseDeep),
      Symptom.headache => (icon: Icons.psychology_alt_rounded, color: Palette.violet),
      Symptom.nausea => (icon: Icons.sick_rounded, color: Palette.teal),
      Symptom.swelling => (icon: Icons.back_hand_rounded, color: Palette.blue),
    };

class FloStyleCalendarDrawer extends StatelessWidget {
  final DateTime day;
  final DayLog log;
  final void Function(Mood) onToggleMood;
  final void Function(Symptom) onToggleSymptom;
  final VoidCallback onKick;
  final VoidCallback onResetKicks;

  const FloStyleCalendarDrawer({
    super.key,
    required this.day,
    required this.log,
    required this.onToggleMood,
    required this.onToggleSymptom,
    required this.onKick,
    required this.onResetKicks,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Palette.bgElevated,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(l.t('log_title'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(ml.formatFullDate(day),
                  style: const TextStyle(color: Palette.textDim, fontSize: 13)),
              const SizedBox(height: 20),

              // ---- Mood ----
              _SectionLabel(l.t('log_mood')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in Mood.values)
                    _PillButton(
                      icon: _moodStyle(m).icon,
                      color: _moodStyle(m).color,
                      label: l.t('mood_${m.name}'),
                      selected: log.mood == m,
                      onTap: () => onToggleMood(m),
                    ),
                ],
              ),
              const SizedBox(height: 22),

              // ---- Symptoms ----
              _SectionLabel(l.t('log_symptoms')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in Symptom.values)
                    _PillButton(
                      icon: _symptomStyle(s).icon,
                      color: _symptomStyle(s).color,
                      label: l.t('sym_${s.name}'),
                      selected: log.symptoms.contains(s),
                      onTap: () => onToggleSymptom(s),
                    ),
                ],
              ),
              const SizedBox(height: 22),

              // ---- Fetal kick counter ----
              _SectionLabel(l.t('log_kicks')),
              const SizedBox(height: 10),
              _KickCounter(kicks: log.kicks, onKick: onKick, onReset: onResetKicks),
              const SizedBox(height: 8),

              // Done
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.t('onb_finish')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      );
}

/// A large, illustrated pill button (≥48dp tall). Unselected = soft grey fill;
/// selected = the option's own accent tint + coloured border and icon.
class _PillButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PillButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.14) : Palette.glass,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: selected ? color.withValues(alpha: 0.55) : Palette.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: selected ? color : Palette.textDim),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? Palette.text : Palette.textDim,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fetal kick counter: a big "+" hit target, the running count, and a reset.
class _KickCounter extends StatelessWidget {
  final int kicks;
  final VoidCallback onKick;
  final VoidCallback onReset;
  const _KickCounter({required this.kicks, required this.onKick, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Palette.rose.withValues(alpha: 0.12), Palette.violet.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: Palette.rose.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$kicks',
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 30, fontWeight: FontWeight.w700, height: 1)),
                  const SizedBox(width: 6),
                  Text(l.t('kick_today'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 13)),
                ],
              ),
              if (kicks > 0)
                TextButton(
                  onPressed: () async {
                    final ok = await confirmDestructive(
                      context,
                      title: l.t('confirm_reset_kicks_title'),
                      message: l.t('confirm_reset_kicks_body'),
                      confirmLabel: l.t('kick_reset'),
                    );
                    if (ok) onReset();
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                  child: Text(l.t('kick_reset'), style: const TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
          const Spacer(),
          // Large "+" hit target
          Semantics(
            button: true,
            label: l.t('kick_add'),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onKick,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: Palette.roseViolet,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Palette.rose.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -4)],
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 34),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
