/// The postpartum recovery screen — the mother's own recovery after birth.
///
/// Two halves, deliberately. The top is calm: what is ordinary around now, and
/// the six-week check to aim for. The bottom is the opposite — a short,
/// unmissable list of signs that mean "call now", set apart so it is never
/// softened by the reassurance above it.
///
/// Nothing here diagnoses. The recovery notes describe what is usual; the
/// warning list points OUTWARD, to a clinic, on purpose.
library;

import 'package:flutter/material.dart';

import '../../domain/postpartum.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class PostpartumScreen extends StatelessWidget {
  final DateTime birthDate;
  final DateTime today;
  const PostpartumScreen({super.key, required this.birthDate, required this.today});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final days = daysSinceBirth(birthDate, today);
    final notes = notesNow(days);
    final untilCheck = daysUntilCheck(days);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('pp_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // The disclaimer sits first: it changes how everything below is read.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Palette.glass,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 17, color: Palette.textDim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l.t('pp_disclaimer'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.45)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // What is ordinary around now.
          _Title(l.t('pp_now_title')),
          for (final n in notes) _NoteRow(note: n),
          const SizedBox(height: 18),

          // The six-week check — the thing the app cannot do and this can.
          _CheckCard(untilCheck: untilCheck),
          const SizedBox(height: 22),

          // Set apart: the signs that mean call now.
          _WarningBlock(),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Palette.textDim)),
      );
}

IconData _areaIcon(RecoveryArea area) => switch (area) {
      RecoveryArea.bleeding => Icons.water_drop_outlined,
      RecoveryArea.body => Icons.self_improvement_outlined,
      RecoveryArea.emotional => Icons.favorite_outline,
      RecoveryArea.care => Icons.local_cafe_outlined,
    };

Color _areaColour(RecoveryArea area) => switch (area) {
      RecoveryArea.bleeding => Palette.roseDeep,
      RecoveryArea.body => Palette.teal,
      RecoveryArea.emotional => Palette.violet,
      RecoveryArea.care => Palette.rose,
    };

String _areaLabel(dynamic l, RecoveryArea area) => switch (area) {
      RecoveryArea.bleeding => l.t('pp_area_bleeding'),
      RecoveryArea.body => l.t('pp_area_body'),
      RecoveryArea.emotional => l.t('pp_area_emotional'),
      RecoveryArea.care => l.t('pp_area_care'),
    };

class _NoteRow extends StatelessWidget {
  final RecoveryNote note;
  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final colour = _areaColour(note.area);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_areaIcon(note.area), size: 18, color: colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_areaLabel(l, note.area),
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: colour)),
                const SizedBox(height: 3),
                Text(l.t('pp_note_${note.id}'),
                    style: const TextStyle(fontSize: 13.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  final int? untilCheck;
  const _CheckCard({required this.untilCheck});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.violet.withValues(alpha: 0.12), Palette.rose.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: Palette.violet.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Palette.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_outlined, size: 20, color: Palette.violet),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('pp_check_title'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  untilCheck != null ? l.t('pp_check_in', {'n': untilCheck}) : l.t('pp_check_past'),
                  style: const TextStyle(color: Palette.violet, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(l.t('pp_check_body'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The warning list, set apart with its own warm frame so it is never read as
/// part of the reassurance above.
class _WarningBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Palette.roseDeep.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.roseDeep.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 19, color: Palette.roseDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.t('pp_warn_title'),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Palette.roseDeep)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.t('pp_warn_intro'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          for (final id in warningSigns)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Palette.roseDeep, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l.t('pp_warn_$id'),
                        style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
