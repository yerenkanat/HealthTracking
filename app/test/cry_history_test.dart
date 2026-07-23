/// Cry-analysis history: the CryResult round-trip, the controller's capped
/// newest-first store, and that it survives a persist → reload.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/persisted_config.dart';
import 'package:fcs_app/domain/cry_analysis.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';

PersistedConfig _cfg({List<CryResult> cryHistory = const []}) => PersistedConfig(
      onboarded: true, locale: AppLocale.ru, profile: const UserProfile(),
      children: const [], devices: const [], cryHistory: cryHistory);

CryAnalysis _analysis(String reason, double conf) => CryAnalysis(
      primaryReason: reason, confidence: conf, probabilities: {reason: (conf * 100).round()}, recommendationRu: '');

void main() {
  test('CryResult round-trips through JSON', () {
    final r = CryResult(reason: 'hungry', confidence: 0.84, at: DateTime.utc(2026, 7, 23, 9, 30));
    final back = CryResult.fromJson(r.toJson());
    expect(back.reason, 'hungry');
    expect(back.confidence, 0.84);
    expect(back.at, DateTime.utc(2026, 7, 23, 9, 30));
    expect(back.confidencePct, 84);
    expect(back.reasonEnum, CryReason.hungry);
  });

  test('a malformed CryResult degrades instead of throwing', () {
    final r = CryResult.fromJson({'reason': 'weird', 'confidence': 'x', 'at': 'nope'});
    expect(r.reason, 'weird');
    expect(r.confidence, 0.0);
    expect(r.reasonEnum, isNull); // unknown code
  });

  group('controller cry history', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('recordCry stores newest-first', () {
      final c = make();
      addTearDown(c.dispose);
      c.recordCry(_analysis('tired', 0.5));
      c.recordCry(_analysis('hungry', 0.9));
      expect(c.cryHistory.map((e) => e.reason).toList(), ['hungry', 'tired']);
    });

    test('history is capped at 20', () {
      final c = make();
      addTearDown(c.dispose);
      for (var i = 0; i < 25; i++) {
        c.recordCry(_analysis('hungry', 0.5));
      }
      expect(c.cryHistory, hasLength(20));
    });
  });

  test('cry history survives a PersistedConfig round-trip', () {
    final cfg = _cfg(cryHistory: [
      CryResult(reason: 'hungry', confidence: 0.84, at: DateTime.utc(2026, 7, 23, 9)),
      CryResult(reason: 'tired', confidence: 0.6, at: DateTime.utc(2026, 7, 22, 20)),
    ]);
    final back = PersistedConfig.decode(cfg.encode());
    expect(back.cryHistory, hasLength(2));
    expect(back.cryHistory.first.reason, 'hungry');
    expect(back.cryHistory.first.confidencePct, 84);
  });

  test('a config with no cry history reads as empty', () {
    final back = PersistedConfig.decode(_cfg().encode());
    expect(back.cryHistory, isEmpty);
  });
}
