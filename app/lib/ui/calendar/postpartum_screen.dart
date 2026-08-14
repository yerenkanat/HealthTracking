/// The postpartum recovery screen — the mother's own recovery after birth.
///
/// Two halves, deliberately. The top is calm: what is ordinary around now, and
/// the six-week check to aim for. The bottom is the opposite — a short,
/// unmissable list of signs that mean "call now", set apart so it is never
/// softened by the reassurance above it.
///
/// Nothing here diagnoses. The recovery notes describe what is usual; the
/// warning list points OUTWARD, to a clinic, on purpose.
///
/// BETWEEN THE TWO HALVES, «Как вы себя чувствуете».
///
/// The calm half described mood and the warning half named thoughts of harm,
/// and there was nothing in between — no way to say how today went, and no way
/// for the app to notice a month of bad weeks in the diary it was already
/// keeping. The mood row writes the SAME [DayLog] the calendar writes (so it
/// syncs on the existing path and reaches the back office's diary), and four
/// low weeks in a row raise the amber card that offers the screening
/// questionnaire. Everything the questionnaire concludes ends up back at the
/// warning block below, which is the only place this screen is allowed to send
/// her.
library;

import 'package:flutter/material.dart' hide Flow;

import '../../app/app_controller.dart';
import '../../domain/cycle_log.dart';
import '../../domain/epds.dart';
import '../../domain/postpartum.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';
import 'epds_screen.dart';
import 'logging_drawer.dart' show moodStyle;

class PostpartumScreen extends StatelessWidget {
  final DateTime birthDate;
  final DateTime today;

  /// Her own data. Optional ONLY so the layout suites (overflow, narrow phone)
  /// can render the screen without building a controller; every real caller
  /// passes one, and without it the mood row and the screening offer are simply
  /// not drawn — there is nothing to write to and nothing to read a run from.
  final AppController? controller;

  const PostpartumScreen({
    super.key,
    required this.birthDate,
    required this.today,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final days = daysSinceBirth(birthDate, today);
    final notes = notesNow(days);
    final untilCheck = daysUntilCheck(days);
    final c = controller;

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
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: Palette.glass,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 17, color: Palette.textDim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l.t('pp_disclaimer'),
                      style: const TextStyle(
                          color: Palette.textDim,
                          fontSize: 12.5,
                          height: 1.45)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // How she is TODAY, before the general notes: it is the one thing on
          // this screen only she can supply, and it is what everything below
          // reads from.
          if (c != null) ...[
            _MoodSection(controller: c, today: today),
            const SizedBox(height: 18),
            _ScreeningCard(controller: c, today: today),
            const SizedBox(height: 18),
          ],

          // What is ordinary around now.
          _Title(l.t('pp_now_title')),
          for (final n in notes) _NoteRow(note: n),
          const SizedBox(height: 18),

          // The six-week check — the thing the app cannot do and this can.
          _CheckCard(untilCheck: untilCheck),
          const SizedBox(height: 22),

          // Set apart: the signs that mean call now.
          const PostpartumWarningBlock(),
        ],
      ),
    );
  }
}

/// «Как вы себя чувствуете» — one tap, into the day log she already keeps.
///
/// Writes through `AppController.toggleMoodFor`, which is `setDayLog`, which
/// fires the existing cycle-sync hook. No new sync, no new table, and the mood
/// appears in the back office's «Дневник» beside the ones she logs from the
/// calendar — because it IS one of those.
class _MoodSection extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  const _MoodSection({required this.controller, required this.today});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // Rebuilt on every controller change so the tap lights up immediately —
    // the controller persists and re-emits, exactly as the logging drawer does.
    // AppController is not a Listenable; `changes` is the stream every other
    // screen in this folder subscribes to.
    return StreamBuilder<void>(
      stream: controller.changes,
      builder: (context, _) {
        final log = controller.logFor(today);
        return DsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('pp_mood_title'),
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(l.t('pp_mood_hint'),
                  style: const TextStyle(
                      color: Palette.textDim, fontSize: 12.5, height: 1.4)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in Mood.values)
                    _MoodButton(
                      mood: m,
                      selected: log.mood == m,
                      onTap: () => controller.toggleMoodFor(today, m),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // The frame's «Отметить самочувствие» line. It says which state
              // the row is in rather than repeating the instruction: a woman
              // who has already tapped needs confirmation, not a second nudge.
              Row(
                children: [
                  Icon(
                    log.mood == null
                        ? Icons.touch_app_outlined
                        : Icons.check_circle_outline,
                    size: 16,
                    color: log.mood == null ? Palette.textDim : Palette.good,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      log.mood == null
                          ? l.t('pp_mood_cta')
                          : l.t('pp_mood_saved'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color:
                              log.mood == null ? Palette.textDim : Palette.good),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MoodButton extends StatelessWidget {
  final Mood mood;
  final bool selected;
  final VoidCallback onTap;
  const _MoodButton(
      {required this.mood, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final style = moodStyle(mood);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: DsShape.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? style.color.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? style.color : Ds.hairline,
            width: DsShape.borderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 20, color: style.color),
            const SizedBox(width: 7),
            Text(l.t('mood_${mood.name}'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// The screening offer. Amber and named when her own entries have run low for
/// four weeks; quiet otherwise — but present either way, because a woman who
/// never logs a mood is not a woman who is fine.
class _ScreeningCard extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  const _ScreeningCard({required this.controller, required this.today});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return StreamBuilder<void>(
      stream: controller.changes,
      builder: (context, _) {
        final run = lowMoodWeekRun(controller.dayLogs, today);
        final raised = run >= lowMoodRunThreshold;
        final last = controller.lastEpds;
        final accent = raised ? Palette.amber : Palette.violet;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: accent.withValues(alpha: raised ? 0.16 : 0.10),
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: Ds.ink, width: DsShape.borderWidth),
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                        raised
                            ? Icons.wb_twilight_outlined
                            : Icons.favorite_outline,
                        size: 20,
                        color: raised ? Ds.amberText : accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          raised
                              ? (run == lowMoodRunThreshold
                                  ? l.t('pp_low_run_title')
                                  : l.t('pp_low_run_title_n', {'n': run}))
                              : l.t('pp_screen_offer_title'),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          raised
                              ? l.t('pp_low_run_body')
                              : l.t('pp_screen_offer_body'),
                          style: const TextStyle(
                              color: Palette.textDim,
                              fontSize: 12.5,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (last != null) ...[
                const SizedBox(height: 10),
                Text(
                  l.t('pp_screen_last', {
                    'd': MaterialLocalizations.of(context)
                        .formatMediumDate(last.takenAt),
                    'n': last.score,
                  }),
                  style:
                      const TextStyle(color: Palette.textDim, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              DsSecondaryButton(
                label: l.t('epds_entry'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EpdsScreen(onCompleted: controller.recordEpds),
                )),
              ),
            ],
          ),
        );
      },
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
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Palette.textDim)),
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
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
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
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: colour)),
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
        color: Palette.violet.withValues(alpha: 0.12),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: Palette.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_outlined,
                size: 20, color: Palette.violet),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('pp_check_title'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  untilCheck != null
                      ? l.t('pp_check_in', {'n': untilCheck})
                      : l.t('pp_check_past'),
                  style: const TextStyle(
                      color: Palette.violet,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(l.t('pp_check_body'),
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5, height: 1.4)),
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
///
/// Public because the screening result ends here too. That is the point of the
/// whole questionnaire: whatever it scores, the only thing it may do is show
/// her THIS list — the same words, in the same frame, not a softened restatement
/// written for the result screen.
class PostpartumWarningBlock extends StatelessWidget {
  const PostpartumWarningBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Palette.roseDeep.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 19, color: Palette.roseDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.t('pp_warn_title'),
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Palette.roseDeep)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.t('pp_warn_intro'),
              style: const TextStyle(
                  color: Palette.textDim, fontSize: 12.5, height: 1.4)),
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
                      decoration: const BoxDecoration(
                          color: Palette.roseDeep, shape: BoxShape.circle),
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
