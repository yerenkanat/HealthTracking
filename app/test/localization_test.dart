/// Widget-level localization tests (run with `flutter test`).
/// Confirms the same screen renders Russian / Kazakh / English via L10nScope,
/// and that the language switcher fires the change callback.
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';

void main() {
  Widget wrap(AppLocale? locale, Widget child) {
    final content = locale == null ? child : L10nScope(l10n: L10n(locale), child: child);
    return MaterialApp(home: content);
  }

  // These three used to key off «Записывайте вручную» / «Қолмен жазыңыз» /
  // «Log it yourself» — the manual-entry card's heading, which was the only
  // text on an empty dashboard. That card was removed with hand entry on
  // 2026-08-17. The screen's own title carries the same three languages and is
  // on the page in every state, which is what these tests are actually about.
  testWidgets('empty state renders in Russian by default scope', (tester) async {
    await tester.pumpWidget(wrap(AppLocale.ru, const HealthDashboardView(samples: [])));
    expect(find.text('Ваше здоровье'), findsOneWidget);
  });

  testWidgets('empty state renders in Kazakh', (tester) async {
    await tester.pumpWidget(wrap(AppLocale.kk, const HealthDashboardView(samples: [])));
    expect(find.text('Сіздің денсаулығыңыз'), findsOneWidget);
  });

  testWidgets('falls back to English with no scope', (tester) async {
    await tester.pumpWidget(wrap(null, const HealthDashboardView(samples: [])));
    expect(find.text('Your health'), findsOneWidget);
  });

  testWidgets('language switcher fires onLocaleChange', (tester) async {
    AppLocale? picked;
    await tester.pumpWidget(wrap(
      AppLocale.ru,
      HealthDashboardView(
        samples: const [],
        currentLocale: AppLocale.ru,
        onLocaleChange: (l) => picked = l,
      ),
    ));
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(picked, AppLocale.en);
  });
}
