/// The postpartum screening questionnaire — frame 30, «Опросник · 10 вопросов».
///
/// Ten questions, four answers each, then one number and one sentence about
/// what to do with it. The screen deliberately does very little: the scoring
/// lives in `domain/epds.dart` (where the seven reverse-scored items are pinned
/// by a verifier), and the "call someone" half is the SAME warning block the
/// recovery screen already ends with — the one that points outward.
///
/// THREE RULES THIS FILE OBEYS
///
///   1. It never prints a diagnosis. Not in a title, not in a band label, not
///      in a colour that reads as one. The strongest thing it may say is
///      «поговорите с врачом», and it says that by showing the outward block.
///   2. The ten answers never leave this widget. `_finish` totals them, builds
///      an [EpdsResult] (id + date + score) and hands THAT to the caller. There
///      is no code path from `_answers` to storage, and item 10 is the reason.
///   3. Item 10 outranks the total. A calm sheet with one mark on item 10
///      routes outward exactly as a 20 does — see [routesOutward].
library;

import 'package:flutter/material.dart';

import '../../core/uuid.dart';
import '../../domain/epds.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';
import 'postpartum_screen.dart' show PostpartumWarningBlock;

class EpdsScreen extends StatefulWidget {
  /// Called once, with the finished screening, when she reaches the result.
  /// The caller persists and syncs it; this screen keeps nothing.
  final void Function(EpdsResult) onCompleted;

  /// Injected for tests — the result carries a timestamp, and a test cannot
  /// assert on `DateTime.now()`.
  final DateTime Function() now;

  /// Injected for tests, same reason: an id that changes every run cannot be
  /// asserted on.
  final String Function() newId;

  const EpdsScreen({
    super.key,
    required this.onCompleted,
    DateTime Function()? now,
    String Function()? newId,
  })  : now = now ?? DateTime.now,
        newId = newId ?? uuidV4;

  @override
  State<EpdsScreen> createState() => _EpdsScreenState();
}

class _EpdsScreenState extends State<EpdsScreen> {
  /// Printed-option index per item, null until answered. Never persisted,
  /// never pushed, and discarded with the widget.
  final List<int?> _answers = List<int?>.filled(epdsItemCount, null);

  /// Set once she presses «Показать результат». Its presence is what swaps the
  /// questionnaire for the result.
  EpdsResult? _result;
  bool _selfHarm = false;
  bool _showIncomplete = false;

  void _finish() {
    if (!isComplete(_answers)) {
      setState(() => _showIncomplete = true);
      return;
    }
    final answers = [for (final a in _answers) a!];
    final result = EpdsResult(
      id: widget.newId(),
      takenAt: widget.now(),
      score: epdsTotal(answers),
    );
    // The only thing that crosses out of this widget. `answers` dies with the
    // method; `result` carries a date and a number.
    widget.onCompleted(result);
    setState(() {
      _selfHarm = flaggedSelfHarm(answers);
      _result = result;
    });
  }

  void _retake() => setState(() {
        for (var i = 0; i < _answers.length; i++) {
          _answers[i] = null;
        }
        _result = null;
        _selfHarm = false;
        _showIncomplete = false;
      });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final answered = _answers.where((a) => a != null).length;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
          backgroundColor: Palette.bg, title: Text(l.t('epds_title'))),
      body: _result != null
          ? _Result(
              result: _result!,
              selfHarm: _selfHarm,
              onRetake: _retake,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // What this is, before the first question rather than after the
                // last: a woman who reads the disclaimer only at the end has
                // already answered ten questions believing something else.
                _Disclaimer(),
                const SizedBox(height: 16),
                Text(l.t('epds_period'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Palette.textDim)),
                const SizedBox(height: 12),

                for (var i = 1; i <= epdsItemCount; i++) ...[
                  _Question(
                    item: i,
                    chosen: _answers[i - 1],
                    onPick: (o) => setState(() {
                      _answers[i - 1] = o;
                      _showIncomplete = false;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_showIncomplete) ...[
                  Text(l.t('epds_incomplete'),
                      style: const TextStyle(
                          color: Palette.roseDeep,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                ],
                Text(l.t('epds_progress', {'n': answered}),
                    style:
                        const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                const SizedBox(height: 10),
                DsPrimaryButton(
                  label: l.t('epds_submit'),
                  // Enabled even when incomplete, on purpose: a dead button
                  // explains nothing, and «ответьте на все десять» does.
                  onPressed: _finish,
                ),
              ],
            ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        color: Palette.glass,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 17, color: Palette.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.t('epds_disclaimer'),
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5, height: 1.45)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Named, so nobody has to wonder which questionnaire this is — and so
          // a clinician she shows it to recognises it in one word.
          Text(l.t('epds_instrument'),
              style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l.t('epds_not_validated'),
              style: const TextStyle(
                  color: Palette.textDim, fontSize: 11.5, height: 1.4)),
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  final int item;
  final int? chosen;
  final ValueChanged<int> onPick;
  const _Question({required this.item, required this.chosen, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return DsCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$item. ${l.t('epds_q$item')}',
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.35)),
          const SizedBox(height: 10),
          for (var o = 0; o < epdsOptionCount; o++)
            _Option(
              label: l.t('epds_q${item}_a$o'),
              selected: chosen == o,
              onTap: () => onPick(o),
            ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Option({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: DsShape.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Palette.violet.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Palette.violet : Ds.hairline,
              width: DsShape.borderWidth,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A radio drawn by hand rather than a Radio<int>: the group has to
              // stay inside one question, and the shape has to survive the
              // 130% text scale the narrow-phone suite renders at.
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: selected ? Palette.violet : Palette.textDim,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The result: a number, one sentence about what to do, and — when either route
/// says so — the recovery screen's own outward block.
class _Result extends StatelessWidget {
  final EpdsResult result;
  final bool selfHarm;
  final VoidCallback onRetake;
  const _Result({required this.result, required this.selfHarm, required this.onRetake});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final outward = routesOutward(score: result.score, selfHarm: selfHarm);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        DsCard(
          color: Palette.glass,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('epds_result_title'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Palette.textDim)),
              const SizedBox(height: 6),
              // The number is the honest part and gets the size. It is a score
              // on a named scale, not a verdict, and the sentence under it says
              // what to do rather than what she is.
              Text(l.t('epds_score', {'n': result.score}),
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 8),
              Text(l.t('epds_band_${result.band.name}'),
                  style: const TextStyle(fontSize: 13.5, height: 1.45)),
              const SizedBox(height: 10),
              Text(l.t('epds_saved'),
                  style: const TextStyle(
                      color: Palette.textDim, fontSize: 11.5)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Item 10, raised on its own and BEFORE the warning list, whatever the
        // total said. This is the sentence the whole screen exists for.
        if (selfHarm) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Palette.roseDeep.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.favorite_outline,
                    size: 19, color: Palette.roseDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l.t('epds_harm_flag'),
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color: Palette.roseDeep)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // The outward block — the same one the recovery screen ends with, not a
        // softer copy of it. Shown when the total reached the published
        // threshold OR item 10 was marked.
        if (outward) ...[
          const PostpartumWarningBlock(),
          const SizedBox(height: 14),
        ],

        DsSecondaryButton(label: l.t('epds_retake'), onPressed: onRetake),
        const SizedBox(height: 10),
        DsSecondaryButton(
          label: l.t('epds_close'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
