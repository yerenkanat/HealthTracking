/// The pregnancy weight-gain guide.
///
/// Reference first — the standard ranges by pre-pregnancy BMI, for the mother
/// to match herself to (the app does not know her starting weight) — then the
/// one personal thing it can honestly say: how her logged pace sits against the
/// typical band. A disclaimer leads and the pace note carries its own caveat.
library;

import 'package:flutter/material.dart';

import '../../domain/pregnancy_weight_guide.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class PregnancyWeightScreen extends StatelessWidget {
  /// The mother's average logged gain (kg/week), or null when too few entries.
  final double? weeklyRateKg;
  const PregnancyWeightScreen({super.key, required this.weeklyRateKg});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final loc = l.locale;
    final pace = assessWeeklyPace(weeklyRateKg);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('pwg_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(l.t('pwg_intro'),
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: Palette.text)),
          const SizedBox(height: 20),

          // The reference ranges by band.
          _Title(l.t('pwg_ranges_title')),
          for (final r in totalGainRanges) _RangeRow(range: r, loc: loc),
          const SizedBox(height: 20),

          // Typical weekly pace.
          _Card(
            title: l.t('pwg_weekly_title'),
            child: Text(
              l.t('pwg_weekly_body', {
                'low': _fmt(typicalWeeklyLowKg, loc),
                'high': _fmt(typicalWeeklyHighKg, loc),
                't1low': _fmt(firstTrimesterLowKg, loc),
                't1high': _fmt(firstTrimesterHighKg, loc),
              }),
              style: const TextStyle(fontSize: 13, height: 1.5, color: Palette.textDim),
            ),
          ),
          const SizedBox(height: 12),

          // Her own pace, from what she has logged.
          _Card(
            title: l.t('pwg_your_pace_title'),
            child: pace == null
                ? Text(l.t('pwg_no_data'),
                    style: const TextStyle(fontSize: 13, height: 1.5, color: Palette.textDim))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.t('pwg_your_avg', {'n': _fmt(weeklyRateKg!, loc)}),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_paceIcon(pace), size: 17, color: _paceColour(pace)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l.t('pwg_pace_${pace.name}'),
                                style: TextStyle(fontSize: 13, height: 1.45, color: _paceColour(pace))),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          Text(l.t('pwg_disclaimer'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.45)),
        ],
      ),
    );
  }

  IconData _paceIcon(GainPace p) => switch (p) {
        GainPace.onTrack => Icons.check_circle_outline,
        GainPace.slow => Icons.trending_down_rounded,
        GainPace.fast => Icons.trending_up_rounded,
      };

  Color _paceColour(GainPace p) => switch (p) {
        GainPace.onTrack => Palette.teal,
        GainPace.slow => Palette.violet,
        GainPace.fast => Palette.roseDeep,
      };
}

/// Format a kilo value for the reader: trim a trailing .0, and use the locale's
/// decimal comma for ru/kk (matching the BMI numbers in the band labels).
String _fmt(double v, AppLocale loc) {
  var s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return loc == AppLocale.en ? s : s.replaceAll('.', ',');
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Palette.textDim)),
      );
}

class _RangeRow extends StatelessWidget {
  final GainRange range;
  final AppLocale loc;
  const _RangeRow({required this.range, required this.loc});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(l.t('pwg_band_${range.band.name}'),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Text(
            l.t('pwg_range_value', {'low': _fmt(range.lowKg, loc), 'high': _fmt(range.highKg, loc)}),
            style: const TextStyle(
                fontFamily: 'JetBrainsMono', fontSize: 13.5, fontWeight: FontWeight.w700, color: Palette.violet),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Palette.textDim)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}
