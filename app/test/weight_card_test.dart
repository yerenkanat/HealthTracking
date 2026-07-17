/// Widget tests for the pregnancy weight card (run with `flutter test`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/weight.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/weight_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: L10nScope(l10n: const L10n(AppLocale.en), child: Scaffold(body: child)),
      );

  testWidgets('empty state prompts to log', (tester) async {
    await tester.pumpWidget(wrap(WeightCard(entries: const [], onLog: (_) {})));
    expect(find.text('Log your weight to see the trend.'), findsOneWidget);
  });

  testWidgets('shows latest weight and delta since start', (tester) async {
    const entries = [
      WeightEntry(date: '2026-07-01', kg: 62.0),
      WeightEntry(date: '2026-07-15', kg: 63.4),
    ];
    await tester.pumpWidget(wrap(WeightCard(entries: entries, onLog: (_) {})));
    expect(find.text('63.4'), findsOneWidget);
    expect(find.text('+1.4 kg since start'), findsOneWidget);
  });

  testWidgets('log sheet saves the stepped value', (tester) async {
    double? logged;
    await tester.pumpWidget(wrap(WeightCard(
      entries: const [WeightEntry(date: '2026-07-15', kg: 63.0)],
      onLog: (kg) => logged = kg,
    )));
    await tester.tap(find.text('Log weight'));
    await tester.pumpAndSettle();
    // Seeded at 63.0; tap the stepper's +0.1 twice → 63.2 (the card's own
    // "Log weight" button also uses add_rounded, so target the last one).
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(logged, closeTo(63.2, 1e-9));
  });
}
