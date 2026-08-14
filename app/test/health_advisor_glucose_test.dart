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

  test('a normal glucose earns no reassurance at all', () {
    // CHANGED 2026-08-14, and it is a withdrawal rather than a loosening.
    // «Сахар в норме» was refused sentence #5 in docs/CLINICAL-REVIEW-WATCH.md
    // and shipped word for word — a normality verdict on a diabetes number,
    // from a value whose unit our only source never states. Blood sugar was
    // withdrawn from the admin panel for that reason a day earlier; the app
    // kept saying it.
    //
    // There is no replacement string, deliberately: silence is the whole fix,
    // and a number with no unit cannot be called normal on any scale. Pinned
    // from the other side by test/refused_sentences_test.dart.
    final out = generateAdvisories(_glucoseSamples(5.3));
    expect(_find(out, 'ADV_GLUCOSE_STEADY'), isNull);
    expect(_find(out, 'ADV_GLUCOSE_HIGH'), isNull);
    expect(_find(out, 'ADV_GLUCOSE_LOW'), isNull);
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
