/// "Why is baby crying" — record a short clip and show the classifier's most
/// likely reason, the spread across reasons, and a gentle recommendation.
///
/// The recorder and the API client are injected so the whole flow is testable
/// with fakes (a widget test has neither a microphone nor a network). The screen
/// owns only the small state machine: idle → recording → analysing → result.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cry_classifier_client.dart';
import '../../data/cry_recorder.dart';
import '../../domain/cry_analysis.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

/// How long a clip we capture. The classifier is trained on ~5s windows.
const cryRecordSeconds = 5;

enum _Phase { idle, recording, analyzing, done, micDenied, error }

class CryInsightScreen extends StatefulWidget {
  final CryRecorder recorder;
  final CryClassifierClient client;

  /// Called with each successful analysis, so the caller can save it to history.
  final void Function(CryAnalysis)? onResult;

  /// Recent past results to show below the recorder (newest first). Empty hides
  /// the history section.
  final List<CryResult> history;

  /// How sure the classifier must be before this screen NAMES a reason.
  ///
  /// Served by the back office (кадр 17c) and passed in by the caller, so
  /// raising it does not need a release. Below it the screen says «не уверены»,
  /// keeps the bars and asks for another recording — it does not name a reason
  /// and does not print the recommendation, because a recommendation names the
  /// reason in prose.
  final double minConfidence;

  /// «Это было верно?» — her verdict on the analysis just shown.
  ///
  /// Returns whether it was recorded, so a rating that went nowhere is not
  /// confirmed to her as if it had. Null hides the question entirely (the
  /// caller has nowhere to put an answer).
  final bool Function(String verdict, String? actualReason)? onVerdict;

  const CryInsightScreen({
    super.key,
    required this.recorder,
    required this.client,
    this.onResult,
    this.history = const [],
    this.minConfidence = kCryMinConfidenceDefault,
    this.onVerdict,
  });

  @override
  State<CryInsightScreen> createState() => _CryInsightScreenState();
}

class _CryInsightScreenState extends State<CryInsightScreen> {
  _Phase _phase = _Phase.idle;
  CryAnalysis? _result;
  Timer? _timer;

  /// Her answer about the result on screen, once given. Cleared by a new
  /// recording — the question is about THIS analysis, not about the detector.
  String? _verdict;

  /// She said «нет» and is choosing what it actually was.
  bool _pickingReason = false;

  /// The answer could not be saved. Shown instead of a thank-you, because a
  /// rating that silently failed is worse than one never asked for.
  bool _verdictFailed = false;

  @override
  void dispose() {
    _timer?.cancel();
    widget.recorder.dispose();
    super.dispose();
  }

  /// Record her answer, and say so only if it was actually stored.
  void _rate(String verdict, {String? actualReason}) {
    final ok = widget.onVerdict?.call(verdict, actualReason) ?? false;
    setState(() {
      _pickingReason = false;
      _verdict = ok ? verdict : null;
      _verdictFailed = !ok;
    });
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.recording;
      _result = null;
      // A new recording is a new question. Carrying the previous answer over
      // would show a tick under an analysis nobody has rated.
      _verdict = null;
      _pickingReason = false;
      _verdictFailed = false;
    });
    final ok = await widget.recorder.start();
    if (!mounted) return;
    if (!ok) {
      setState(() => _phase = _Phase.micDenied);
      return;
    }
    // Auto-stop after the fixed window; the user doesn't have to time it.
    _timer = Timer(const Duration(seconds: cryRecordSeconds), _finish);
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _phase = _Phase.analyzing);
    final bytes = await widget.recorder.stopAndRead();
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _phase = _Phase.error);
      return;
    }
    try {
      final result = await widget.client.analyze(bytes);
      if (!mounted) return;
      widget.onResult?.call(result); // save to history
      setState(() {
        _result = result;
        _phase = _Phase.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar:
          AppBar(backgroundColor: Palette.bg, title: Text(l.t('cry_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.t('cry_intro'),
                  style: const TextStyle(
                      color: Palette.textDim, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 10),
              // Above the button, not below the result. This is the only screen
              // in the app that records audio — inside somebody's home, of
              // their baby — and where it goes has to be readable BEFORE the
              // microphone opens. Consent that arrives afterwards is not
              // consent.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 14, color: Palette.textDim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.t('cry_privacy'),
                        style: const TextStyle(
                            color: Palette.textDim, fontSize: 12, height: 1.45)),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _MicButton(
                  phase: _phase,
                  onTap:
                      _phase == _Phase.recording || _phase == _Phase.analyzing
                          ? null
                          : _start),
              const SizedBox(height: 14),
              _statusLine(l),
              if (_phase == _Phase.done && _result != null) ...[
                const SizedBox(height: 20),
                _ResultCard(
                    analysis: _result!, minConfidence: widget.minConfidence),
                // Asked only where a reason was actually named. «Это было
                // верно?» under «не уверены» is a question about nothing.
                if (widget.onVerdict != null &&
                    _result!.confidence >= widget.minConfidence) ...[
                  const SizedBox(height: 12),
                  _VerdictCard(
                    verdict: _verdict,
                    picking: _pickingReason,
                    failed: _verdictFailed,
                    onYes: () => _rate(CryVerdict.correct),
                    onNo: () => setState(() {
                      _pickingReason = true;
                      _verdictFailed = false;
                    }),
                    onActual: (code) =>
                        _rate(CryVerdict.wrong, actualReason: code),
                  ),
                ],
              ],
              if (widget.history.isNotEmpty) ...[
                const SizedBox(height: 24),
                _HistoryCard(
                    history: widget.history,
                    minConfidence: widget.minConfidence),
              ],
              const SizedBox(height: 24),
              Text(l.t('cry_disclaimer'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Palette.textDim,
                      fontSize: 11.5,
                      height: 1.45,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine(L10n l) {
    final (text, colour) = switch (_phase) {
      _Phase.recording => (l.t('cry_recording'), Palette.roseDeep),
      _Phase.analyzing => (l.t('cry_analyzing'), Palette.violet),
      _Phase.micDenied => (l.t('cry_mic_denied'), Palette.danger),
      _Phase.error => (l.t('cry_error'), Palette.danger),
      _ => ('', Palette.textDim),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: colour, fontSize: 13.5, fontWeight: FontWeight.w600));
  }
}

class _MicButton extends StatelessWidget {
  final _Phase phase;
  final VoidCallback? onTap;
  const _MicButton({required this.phase, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final recording = phase == _Phase.recording;
    final busy = phase == _Phase.analyzing;
    final label = switch (phase) {
      _Phase.idle => l.t('cry_record'),
      _Phase.recording => l.t('cry_recording'),
      _Phase.analyzing => l.t('cry_analyzing'),
      _ => l.t('cry_again'),
    };
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label, // a screen reader announces "Record the cry, button" etc.
      excludeSemantics:
          true, // the icon + text below are decorative once labelled
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: recording ? Palette.roseDeep : Ds.coralCta,
                boxShadow: [
                  ...DsShape.hardShadowLg,
                ],
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(38),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 3))
                  : Icon(recording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white, size: 48),
            ),
            const SizedBox(height: 12),
            Text(label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// The label for a reason code, or the generic one for a code this build does
/// not know. Shared by the three cards below, so a server that adds a class
/// cannot make one of them print a raw wire code while the others cope.
String _reasonLabel(L10n l, String code) {
  final known = CryReason.fromCode(code);
  return known == null ? l.t('cry_reason_unknown') : l.t('cry_reason_$code');
}

class _ResultCard extends StatelessWidget {
  final CryAnalysis analysis;

  /// Below this the card names NO reason. See [CryInsightScreen.minConfidence].
  final double minConfidence;

  const _ResultCard({required this.analysis, required this.minConfidence});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // The whole rule of кадр 17c, in one line. Everything below reads off it.
    final sure = analysis.confidence >= minConfidence;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((sure ? l.t('cry_result_title') : l.t('cry_unsure_title'))
              .toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Palette.textDim)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                // Not the reason: «Голод» at 31 % reads exactly like «Голод» at
                // 91 %, and she acts on it the same way.
                child: Text(
                    sure
                        ? _reasonLabel(l, analysis.primaryReason)
                        : l.t('cry_unsure_headline'),
                    style: TextStyle(
                        fontSize: sure ? 22 : 19,
                        fontWeight: FontWeight.w800,
                        color: sure ? null : Palette.textDim)),
              ),
              Text(l.t('cry_confidence', {'n': analysis.confidencePct}),
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: Palette.textDim,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          if (!sure) ...[
            const SizedBox(height: 8),
            // Why there is no answer, and the one thing that helps: a quieter
            // recording. Without this the card is a shrug.
            Text(l.t('cry_unsure_body'),
                style: const TextStyle(
                    color: Palette.textDim, fontSize: 13, height: 1.45)),
          ],
          const SizedBox(height: 16),
          // The bars stay either way. They are the honest form of the same
          // answer — a spread with nothing standing out is exactly what «не
          // уверены» means, and hiding them would leave her with no picture.
          for (final e in analysis.ranked) ...[
            _ReasonBar(
                label: _reasonLabel(l, e.key),
                pct: e.value,
                highlight: sure && e.key == analysis.primaryReason),
            const SizedBox(height: 8),
          ],
          // The recommendation names the reason in prose («Покормите малыша»),
          // so printing it under «не уверены» would say the thing the headline
          // has just refused to say.
          if (sure && analysis.recommendationRu.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                color: Palette.violet.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tips_and_updates_outlined,
                      size: 18, color: Palette.violet),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(analysis.recommendationRu,
                          style: const TextStyle(fontSize: 13.5, height: 1.5))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «Это было верно?» — the only ground truth this product will ever have.
///
/// Nothing in this app knows why a baby cried; the mother who fed him a minute
/// later does. Without this the back office's «точность» could only ever be the
/// model's own confidence under a different name.
class _VerdictCard extends StatelessWidget {
  /// Her answer, once given. Null while the question is still open.
  final String? verdict;
  final bool picking;
  final bool failed;
  final VoidCallback onYes;
  final VoidCallback onNo;
  final void Function(String? actualReason) onActual;

  const _VerdictCard({
    required this.verdict,
    required this.picking,
    required this.failed,
    required this.onYes,
    required this.onNo,
    required this.onActual,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              verdict != null
                  ? l.t('cry_verdict_thanks')
                  : (picking ? l.t('cry_verdict_which') : l.t('cry_verdict_q')),
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              failed
                  ? l.t('cry_verdict_failed')
                  : (verdict != null
                      ? l.t('cry_verdict_why')
                      : l.t('cry_verdict_hint')),
              style: TextStyle(
                  color: failed ? Palette.danger : Palette.textDim,
                  fontSize: 12.5,
                  height: 1.45)),
          if (verdict == null) ...[
            const SizedBox(height: 12),
            // Wrap, not Row: «Не знаю» plus five reason chips do not fit a
            // 360dp phone in one line, least of all at 130 % text.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: picking
                  ? [
                      for (final r in CryReason.values)
                        _Chip(
                            label: _reasonLabel(l, r.code),
                            onTap: () => onActual(r.code)),
                      // «Не знаю» is a real answer: «неверно» is already the
                      // useful half, and forcing a guess would poison the only
                      // ground truth this product has.
                      _Chip(
                          label: l.t('cry_verdict_dont_know'),
                          onTap: () => onActual(null)),
                    ]
                  : [
                      _Chip(label: l.t('cry_verdict_yes'), onTap: onYes, primary: true),
                      _Chip(label: l.t('cry_verdict_no'), onTap: onNo),
                    ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _Chip({required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          // 44 tall: this is a tap target, and a 30px chip is one a tired
          // person misses at 3am.
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: primary ? Ds.coralCta : Palette.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: primary ? Colors.white : null)),
        ),
      ),
    );
  }
}

/// The "recent checks" list — past results, newest first, so a parent can see
/// what the last few cries came back as.
class _HistoryCard extends StatelessWidget {
  final List<CryResult> history;

  /// The same rule as the result card: a past analysis the detector was not
  /// sure about is listed as «не уверены», not as a reason. Naming it here
  /// while refusing to name it above would be the app disagreeing with itself
  /// about the same recording.
  final double minConfidence;

  const _HistoryCard({required this.history, required this.minConfidence});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('cry_history_title').toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Palette.textDim)),
          const SizedBox(height: 8),
          for (var i = 0; i < history.length; i++) ...[
            if (i > 0) const Divider(height: 14, color: Palette.border),
            Row(
              children: [
                Expanded(
                  child: Text(
                      history[i].namesReasonAt(minConfidence)
                          ? _reasonLabel(l, history[i].reason)
                          : l.t('cry_unsure_headline'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: history[i].namesReasonAt(minConfidence)
                              ? null
                              : Palette.textDim)),
                ),
                const SizedBox(width: 8),
                // Flexible: with only the label side Expanded, this one is laid
                // out at its natural width first and the row simply overran —
                // 17px at 130%. "82 % · 15 июл. 2026" is not short text once
                // the font-size slider is up.
                Flexible(
                  child: Text(
                      '${history[i].confidencePct}%  ·  ${ml.formatMediumDate(history[i].at)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Palette.textDim)),
                ),
              ],
            ),
            // Her own verdict, on its own line. The row above is already tight
            // at 130 % text on a 360dp phone; a second line grows downwards,
            // inside a scroll view, where there is room.
            if (history[i].verdict != null) ...[
              const SizedBox(height: 3),
              Text(
                  history[i].verdict == CryVerdict.correct
                      ? l.t('cry_verdict_was_right')
                      : (history[i].actualReason != null
                          ? l.t('cry_verdict_was_wrong_actual',
                              {'reason': _reasonLabel(l, history[i].actualReason!)})
                          : l.t('cry_verdict_was_wrong')),
                  style: const TextStyle(fontSize: 11.5, color: Palette.textDim)),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReasonBar extends StatelessWidget {
  final String label;
  final int pct;
  final bool highlight;
  const _ReasonBar(
      {required this.label, required this.pct, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final colour = highlight ? Palette.violet : Palette.textDim;
    return Row(
      children: [
        SizedBox(
            width: 96,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        highlight ? FontWeight.w700 : FontWeight.w500))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Palette.border,
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
            width: 34,
            child: Text('$pct%',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: colour))),
      ],
    );
  }
}
