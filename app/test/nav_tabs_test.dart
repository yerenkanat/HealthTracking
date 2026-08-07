/// The four tabs, by name, in all three languages.
///
/// docs/CLAUDE-app-design.md §"Таб-бар": «4 вкладки: Сегодня · Календарь ·
/// Ребёнок · Профиль … Подписи переносятся в две строки (казахский длиннее) —
/// высота бара растёт, многоточия нет.»
///
/// The first one read «Здоровье», which names the data the screen holds rather
/// than what a woman opens the app for. She opens it to find out what today
/// needs, and that is what the screen already answers.
///
/// The Kazakh half is the part worth a test rather than a glance: it is the
/// longest of the three, it is the language nobody on the team reads back, and
/// a clipped tab label is invisible in review on a Russian phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/theme.dart';

/// The tabs the shell builds, in order. Kept in one place so this file and
/// home_shell cannot disagree about what "the four tabs" means.
const _keys = ['nav_today', 'nav_calendar', 'nav_child', 'nav_profile'];

const _expected = {
  AppLocale.ru: ['Сегодня', 'Календарь', 'Ребёнок', 'Профиль'],
  AppLocale.kk: ['Бүгін', 'Күнтізбе', 'Бала', 'Профиль'],
  AppLocale.en: ['Today', 'Calendar', 'Child', 'Profile'],
};

void main() {
  group('the four tabs are the four the spec names', () {
    for (final entry in _expected.entries) {
      test('${entry.key.name}', () {
        final l = L10n(entry.key);
        expect([for (final k in _keys) l.t(k)], entry.value);
      });
    }

    test('the first tab is no longer named after the data on it', () {
      // The key was renamed, not just its value: a stale `nav_health` left
      // behind is a string somebody re-uses next month, and it would say
      // «Здоровье» on a tab called «Сегодня».
      for (final locale in AppLocale.values) {
        final l = L10n(locale);
        expect(l.t('nav_health'), isNot(contains('Здоров')),
            reason: 'nav_health should no longer resolve to a real label');
      }
    });
  });

  testWidgets('Kazakh labels wrap rather than clip', (tester) async {
    // 360dp is the narrow phone this is sold on, and 130% text scale is the
    // setting the spec says to check at — the two together are where a clipped
    // label actually appears.
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final l = const L10n(AppLocale.kk);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.kk),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: DsTabBarSurface(
            child: NavigationBar(
              selectedIndex: 0,
              destinations: [
                for (final k in _keys)
                  NavigationDestination(icon: const Icon(Icons.circle_outlined), label: l.t(k)),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The paragraph, not the Text widget. `Text.overflow` is null here — the
    // effective value comes from the theme's DefaultTextStyle — so asserting on
    // the widget passes no matter what the theme says, which is the whole
    // failure this test was written to catch.
    for (final k in _keys) {
      final label = l.t(k);
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: '$k is not on the bar');
      final p = tester.renderObject<RenderParagraph>(finder);

      expect(p.overflow, isNot(TextOverflow.ellipsis),
          reason: '«$label» would be cut to «${label.substring(0, 4)}…»');
      expect(p.didExceedMaxLines, isFalse, reason: '«$label» is truncated by maxLines');

      // What the property checks cannot say: that the whole word actually fits
      // somewhere on the bar. The paragraph is [width] wide and [height] tall;
      // the text needs [maxIntrinsicWidth] laid end to end. If the lines it was
      // given cannot hold that, characters are being painted outside the box.
      final lines = (p.size.height / _lineHeight(tester, l)).round();
      expect(p.size.width * lines, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity)),
          reason: '«$label» needs ${p.getMaxIntrinsicWidth(double.infinity)}px '
              'and has ${p.size.width}px over $lines line(s)');
    }
  });
}

/// The height of one line of tab label, measured from the shortest one.
///
/// «Бала» is four characters in a 90px slot: whatever happens to the others, it
/// is on one line, so its height IS the line height at this text scale.
double _lineHeight(WidgetTester tester, L10n l) {
  final shortest = [for (final k in _keys) l.t(k)]
      .reduce((a, b) => a.length <= b.length ? a : b);
  return tester.renderObject<RenderParagraph>(find.text(shortest)).size.height;
}
