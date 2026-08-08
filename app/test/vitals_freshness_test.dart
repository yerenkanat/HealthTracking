/// «Свежесть данных подписана всегда («2 минуты назад»).»
///
/// docs/CLAUDE-app-design.md §"Тревога и цвет". The four vital-sign cards
/// showed a number and no time, so a heart rate of 118 read as "now" whether it
/// was measured a minute ago or last night — and the reading a woman acts on is
/// the one she believes is current.
///
/// The empty case matters as much: four cards of dashes said nothing about
/// whether the band was off, broken, or simply never worn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  final now = DateTime(2026, 7, 16, 12, 0);

  HealthSample sampleAt(DateTime at) => HealthSample(
        at: at, heartRate: 78, spo2: 98, systolic: 118, diastolic: 76, coreTemp: 36.6,
      );

  Future<void> pump(WidgetTester tester, List<HealthSample> samples,
      {AppLocale locale = AppLocale.ru}) async {
    tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(locale),
      home: L10nScope(
        l10n: L10n(locale),
        child: HealthDashboardView(
          samples: samples,
          sleepNights: const [],
          currentLocale: locale,
          nowForAppointment: now,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The rendered freshness line, or '' when there is none.
  String freshness(WidgetTester tester, AppLocale locale) {
    final l = L10n(locale);
    final prefix = l.t('db_vitals_as_of', {'when': ''}).replaceAll(RegExp(r'\s*$'), '');
    final found = tester.widgetList<Text>(find.byType(Text)).where(
        (t) => (t.data ?? '').startsWith(prefix.split('{').first));
    return found.isEmpty ? '' : (found.first.data ?? '');
  }

  testWidgets('a fresh reading says how fresh', (tester) async {
    await pump(tester, [sampleAt(now.subtract(const Duration(minutes: 2)))]);
    const l = L10n(AppLocale.ru);
    expect(find.text(l.t('db_vitals_as_of', {'when': l.ago(const Duration(minutes: 2))})),
        findsOneWidget);
  });

  testWidgets('the label is above the cards, not under them', (tester) async {
    // A timestamp below four readings is read after they have been believed.
    await pump(tester, [sampleAt(now.subtract(const Duration(minutes: 2)))]);
    const l = L10n(AppLocale.ru);
    final labelY = tester
        .getTopLeft(find.text(l.t('db_vitals_as_of', {'when': l.ago(const Duration(minutes: 2))})))
        .dy;
    final gridY = tester.getTopLeft(find.byType(GridView).first).dy;
    expect(labelY, lessThan(gridY));
  });

  testWidgets('with no readings the dashboard shows its own empty state', (tester) async {
    // Not a second one here. The vitals section only renders when there is a
    // sample, so an empty branch inside the freshness line would be
    // unreachable code pretending to be a safety net — which is what the first
    // version of this was, and what this test caught.
    await pump(tester, const []);
    const l = L10n(AppLocale.ru);
    expect(find.text(l.t('noband_title')), findsOneWidget);
    expect(freshness(tester, AppLocale.ru), '');
  });

  testWidgets('a day-old reading is marked amber, not left looking current', (tester) async {
    await pump(tester, [sampleAt(now.subtract(const Duration(hours: 30)))]);
    final text = tester.widgetList<Text>(find.byType(Text)).firstWhere(
        (t) => (t.data ?? '').contains(const L10n(AppLocale.ru).ago(const Duration(hours: 30))));
    // The MEASURED amber, not the fill: Palette.amber is 2.51:1 at 12px, which
    // the accessibility sweep rejects. A warning nobody can read is not one.
    expect(text.style?.color, Ds.amberText);
    // Amber, never the SOS red — stale data is «нужно внимание», not an alarm.
    expect(text.style?.color, isNot(Palette.danger));
  });

  testWidgets('a recent reading is quiet', (tester) async {
    await pump(tester, [sampleAt(now.subtract(const Duration(minutes: 5)))]);
    final text = tester.widgetList<Text>(find.byType(Text)).firstWhere(
        (t) => (t.data ?? '').contains(const L10n(AppLocale.ru).ago(const Duration(minutes: 5))));
    expect(text.style?.color, Palette.textDim);
  });

  testWidgets('the newest sample wins, whatever order they arrive in', (tester) async {
    // Nothing guarantees the order of what the band flushed, and taking
    // `samples.last` would date the whole screen from a stale row.
    await pump(tester, [
      sampleAt(now.subtract(const Duration(hours: 9))),
      sampleAt(now.subtract(const Duration(minutes: 3))),
      sampleAt(now.subtract(const Duration(hours: 4))),
    ]);
    const l = L10n(AppLocale.ru);
    expect(find.text(l.t('db_vitals_as_of', {'when': l.ago(const Duration(minutes: 3))})),
        findsOneWidget);
  });

  testWidgets('a reading from the future is left unlabelled, not called "in 3 hours"',
      (tester) async {
    // A phone whose clock is wrong must not produce a nonsense sentence beside
    // a medical number.
    await pump(tester, [sampleAt(now.add(const Duration(hours: 3)))]);
    expect(tester.takeException(), isNull);
    const l = L10n(AppLocale.ru);
    // Either nothing, or "just now" — never a future tense.
    final line = freshness(tester, AppLocale.ru);
    expect(line.contains('через'), isFalse);
  });

  testWidgets('it is written in every language', (tester) async {
    for (final locale in AppLocale.values) {
      await pump(tester, [sampleAt(now.subtract(const Duration(minutes: 2)))],
          locale: locale);
      final l = L10n(locale);
      expect(
        find.text(l.t('db_vitals_as_of', {'when': l.ago(const Duration(minutes: 2))})),
        findsOneWidget,
        reason: 'no freshness line in ${locale.name}',
      );
    }
  });
}
