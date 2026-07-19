/// Widget tests for the weight history screen (delete flow).
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/weight.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/weight_history_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        home: L10nScope(l10n: const L10n(AppLocale.en), child: child),
      );

  const entries = [
    WeightEntry(date: '2026-07-01', kg: 62.0),
    WeightEntry(date: '2026-07-08', kg: 62.6),
    WeightEntry(date: '2026-07-15', kg: 63.4),
  ];

  testWidgets('lists entries newest-first with per-entry delta', (tester) async {
    await tester.pumpWidget(wrap(WeightHistoryScreen(entries: entries, onDelete: (_) {})));
    expect(find.text('63.4 kg'), findsOneWidget);
    expect(find.text('62.0 kg'), findsOneWidget);
    expect(find.text('+0.8'), findsOneWidget); // 63.4 − 62.6
  });

  testWidgets('deleting an entry confirms then reports the dateKey', (tester) async {
    String? deleted;
    await tester.pumpWidget(wrap(WeightHistoryScreen(entries: entries, onDelete: (d) => deleted = d)));

    // Delete the newest (first row → 63.4 kg / 2026-07-15).
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete this entry?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(deleted, '2026-07-15');
  });

  testWidgets('empty entries show the prompt', (tester) async {
    await tester.pumpWidget(wrap(WeightHistoryScreen(entries: const [], onDelete: (_) {})));
    expect(find.textContaining('Log your weight'), findsOneWidget);
  });
}
