import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_advisor.dart';
import 'package:fcs_app/domain/health_series.dart';

/// The advisor must actually reason over blood sugar — before this it was
/// displayed on the wellness tile and judged nowhere. A wellness estimate, so it
/// produces a gentle "watch" card, never an emergency.
List<HealthSample> _glucoseSamples(double mmol) {
  final base = DateTime(2026, 7, 24, 9);
  return [
    for (var i = 0; i < 4; i++) HealthSample(at: base.add(Duration(minutes: i * 10)), glucose: mmol),
  ];
}

Advisory? _find(List<Advisory> xs, String code) {
  for (final a in xs) {
    if (a.code == code) return a;
  }
  return null;
}

void main() {
  test('elevated glucose raises a watch advisory, not an emergency', () {
    final out = generateAdvisories(_glucoseSamples(9.0));
    final a = _find(out, 'ADV_GLUCOSE_HIGH');
    expect(a, isNotNull);
    expect(a!.tone, AdviceTone.watch);
    expect(a.metric, 'glucose');
    expect(a.value, 9.0);
  });

  test('low glucose raises a watch advisory', () {
    final out = generateAdvisories(_glucoseSamples(3.4));
    expect(_find(out, 'ADV_GLUCOSE_LOW')?.tone, AdviceTone.watch);
  });

  test('normal glucose is a positive, steady note', () {
    final out = generateAdvisories(_glucoseSamples(5.3));
    expect(_find(out, 'ADV_GLUCOSE_STEADY')?.tone, AdviceTone.positive);
    expect(_find(out, 'ADV_GLUCOSE_HIGH'), isNull);
  });

  test('no glucose samples → no glucose advisory at all', () {
    final base = DateTime(2026, 7, 24, 9);
    final hrOnly = [for (var i = 0; i < 4; i++) HealthSample(at: base.add(Duration(minutes: i)), heartRate: 72)];
    final out = generateAdvisories(hrOnly);
    expect(_find(out, 'ADV_GLUCOSE_HIGH'), isNull);
    expect(_find(out, 'ADV_GLUCOSE_LOW'), isNull);
    expect(_find(out, 'ADV_GLUCOSE_STEADY'), isNull);
  });
}
