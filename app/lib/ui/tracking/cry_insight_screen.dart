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
import '../theme.dart';

/// How long a clip we capture. The classifier is trained on ~5s windows.
const cryRecordSeconds = 5;

enum _Phase { idle, recording, analyzing, done, micDenied, error }

class CryInsightScreen extends StatefulWidget {
  final CryRecorder recorder;
  final CryClassifierClient client;
  const CryInsightScreen({super.key, required this.recorder, required this.client});

  @override
  State<CryInsightScreen> createState() => _CryInsightScreenState();
}

class _CryInsightScreenState extends State<CryInsightScreen> {
  _Phase _phase = _Phase.idle;
  CryAnalysis? _result;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    widget.recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.recording;
      _result = null;
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
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('cry_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.t('cry_intro'),
                  style: const TextStyle(color: Palette.textDim, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 22),
              _MicButton(phase: _phase, onTap: _phase == _Phase.recording || _phase == _Phase.analyzing ? null : _start),
              const SizedBox(height: 14),
              _statusLine(l),
              if (_phase == _Phase.done && _result != null) ...[
                const SizedBox(height: 20),
                _ResultCard(analysis: _result!),
              ],
              const SizedBox(height: 24),
              Text(l.t('cry_disclaimer'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.textDim, fontSize: 11.5, height: 1.45, fontStyle: FontStyle.italic)),
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
    return Text(text, textAlign: TextAlign.center, style: TextStyle(color: colour, fontSize: 13.5, fontWeight: FontWeight.w600));
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
      excludeSemantics: true, // the icon + text below are decorative once labelled
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
          Container(
            width: 116, height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: recording ? null : Palette.violetPink,
              color: recording ? Palette.roseDeep : null,
              boxShadow: [
                BoxShadow(color: (recording ? Palette.roseDeep : Palette.violet).withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 2),
              ],
            ),
            child: busy
                ? const Padding(padding: EdgeInsets.all(38), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : Icon(recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final CryAnalysis analysis;
  const _ResultCard({required this.analysis});

  String _reasonLabel(L10n l, String code) {
    final known = CryReason.fromCode(code);
    return known == null ? l.t('cry_reason_unknown') : l.t('cry_reason_$code');
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('cry_result_title').toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Palette.textDim)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(_reasonLabel(l, analysis.primaryReason),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              Text(l.t('cry_confidence', {'n': analysis.confidencePct}),
                  style: const TextStyle(fontSize: 12.5, color: Palette.textDim, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          for (final e in analysis.ranked) ...[
            _ReasonBar(label: _reasonLabel(l, e.key), pct: e.value, highlight: e.key == analysis.primaryReason),
            const SizedBox(height: 8),
          ],
          if (analysis.recommendationRu.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.violet.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tips_and_updates_outlined, size: 18, color: Palette.violet),
                  const SizedBox(width: 10),
                  Expanded(child: Text(analysis.recommendationRu, style: const TextStyle(fontSize: 13.5, height: 1.5))),
                ],
              ),
            ),
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
  const _ReasonBar({required this.label, required this.pct, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final colour = highlight ? Palette.violet : Palette.textDim;
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: highlight ? FontWeight.w700 : FontWeight.w500))),
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
        SizedBox(width: 34, child: Text('$pct%', textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colour))),
      ],
    );
  }
}
