/// What the temperature on screen is, when a device produced it.
///
/// One widget, used everywhere the number is drawn: the vitals grid on the
/// dashboard, and the metric detail screen she opens by tapping it. Shared
/// rather than copied, because the copy is approved copy — a second version
/// would be a second vocabulary, and the review's whole complaint about the
/// old qualifier was that the claim was not made where the number is.
///
/// It says what the reading cannot tell her and stops. It does not promise that
/// the app will warn her if something is wrong — refused sentence #12
/// (docs/CLINICAL-REVIEW-WATCH.md), because that turns every gap in coverage
/// into an implied all-clear.
///
/// Hidden when there is no temperature, and when the latest one came off a
/// thermometer she used: none of this applies to that, and a qualifier attached
/// to a real measurement teaches her to ignore the qualifier where it matters.
library;

import 'package:flutter/material.dart';

import '../../domain/health_series.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class DeviceTempNote extends StatelessWidget {
  final List<HealthSample> samples;

  /// Vertical breathing room above the note. The grid wants it tight under the
  /// cards; the detail screen sits it in a list that spaces itself.
  final double topPadding;

  const DeviceTempNote({super.key, required this.samples, this.topPadding = 10});

  @override
  Widget build(BuildContext context) {
    final hasTemp = samples.any((s) => s.coreTemp != null);
    if (!hasTemp) return const SizedBox.shrink();
    if (latestSourceFor(samples, 'temp') == ReadingSource.manual) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 15, color: Palette.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              L10nScope.of(context).t('temp_device_estimate_note'),
              style: const TextStyle(
                  color: Palette.textDim, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
