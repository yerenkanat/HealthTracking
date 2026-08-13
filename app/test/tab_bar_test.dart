/// The tab bar against the design spec.
///
/// It is the only surface visible from every screen, and nothing tested it at
/// all — so it was the one place the system's own rule, "black-ink 2px outlines
/// on every surface", was not applied. The bar had no edge and floated against
/// whatever was behind it.
///
/// Two of the spec's values are deliberately NOT met, and the reasons are in
/// design_system.dart: the inactive label is #70597C rather than the spec's
/// #A895B3, which measures 2.9:1 on cream and is unreadable at 11px, and the
/// active label is #B30030 rather than #FF3D71 for the same reason. Those are
/// documented deviations, so this asserts contrast rather than the hex.
///
/// It drives the REAL [HomeShell]. It used to build a two-destination bar of
/// its own labelled «Здоровье» and «Я» — names from a retired spec — and assert
/// styling on that, so the four destinations the app actually ships had no
/// structural test at all and the bar could have grown a fifth tab, lost one,
/// or reordered them without a single failure.
library;

import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

/// docs/CLAUDE-app-design.md §2.15: «Сегодня ☀ · Календарь ▦ · Ребёнок ◎ ·
/// Профиль ☺» — four, in this order. Not a deviation, and not five.
const _keys = ['nav_today', 'nav_calendar', 'nav_child', 'nav_profile'];

/// A label ON THE BAR. Scoped, because «Ребёнок» is also a segment of the
/// calendar's own switch — an unscoped finder matches both and taps neither
/// reliably.
Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  /// The real shell, so the bar under test is the one that ships.
  ///
  /// L10nScope wraps MaterialApp rather than sitting at `home:`: below the
  /// Navigator every pushed route falls back to English, silently.
  Future<AppController> pump(WidgetTester tester,
      {AppLocale locale = AppLocale.ru}) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = AppController(locale: locale);
    addTearDown(c.dispose);
    await tester.pumpWidget(L10nScope(
      l10n: L10n(locale),
      child: MaterialApp(
        theme: FcsTheme.light(locale),
        home: HomeShell(controller: c, catalog: const ContentCatalog({})),
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('the shell ships exactly the four destinations the spec names',
      (tester) async {
    await pump(tester);
    const l = L10n(AppLocale.ru);

    final bar = tester.widget<NavigationBar>(find.descendant(
        of: find.byType(DsTabBarSurface), matching: find.byType(NavigationBar)));

    expect(bar.destinations.length, 4,
        reason: 'the spec names four tabs — not three, and not a Курс fifth');
    expect(
      [
        for (final d in bar.destinations)
          ((d as NavigationDestination).label)
      ],
      [for (final k in _keys) l.t(k)],
      reason: 'the destinations are not the four the spec names, in its order',
    );
    // Each one is on the screen and reachable, not merely declared.
    for (final k in _keys) {
      expect(tab(l.t(k)), findsOneWidget, reason: '$k is not on the bar');
    }
    expect(bar.selectedIndex, 0, reason: 'the app opens on «Сегодня»');
  });

  testWidgets('each destination selects its own tab, in order', (tester) async {
    await pump(tester);
    const l = L10n(AppLocale.ru);

    for (final (i, k) in _keys.indexed) {
      await tester.tap(tab(l.t(k)));
      await tester.pumpAndSettle();
      final bar = tester.widget<NavigationBar>(find.descendant(
          of: find.byType(DsTabBarSurface),
          matching: find.byType(NavigationBar)));
      expect(bar.selectedIndex, i,
          reason: '«${l.t(k)}» does not select tab $i — the labels and the '
              'pages are out of step');
    }
  });

  testWidgets('and they are the same four in Kazakh', (tester) async {
    // The longest of the three languages, and the one nobody on the team reads
    // back — a tab that lost its label here is invisible in review.
    await pump(tester, locale: AppLocale.kk);
    const l = L10n(AppLocale.kk);
    for (final k in _keys) {
      expect(tab(l.t(k)), findsOneWidget, reason: '$k is not on the bar');
    }
  });

  testWidgets('the bar sits on a 2px ink edge', (tester) async {
    await pump(tester);
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(DsTabBarSurface), matching: find.byType(DecoratedBox)).first,
    );
    final border = (box.decoration as BoxDecoration).border as Border;
    expect(border.top.color, Ds.ink);
    expect(border.top.width, DsShape.borderWidth);
    // Only the top. A box around the bar would read as a floating card, not as
    // the page's bottom edge.
    expect(border.bottom, BorderSide.none);
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);
  });

  testWidgets('the bar blurs what scrolls under it', (tester) async {
    // The spec allows blur in exactly two places and this is one of them; it is
    // what makes a 94%-opaque bar read as glass rather than a flat strip.
    await pump(tester);
    expect(
      find.descendant(of: find.byType(DsTabBarSurface), matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    // Bounded, or the filter samples the whole layer and blurs the screen above
    // the bar too.
    expect(
      find.descendant(of: find.byType(DsTabBarSurface), matching: find.byType(ClipRect)),
      findsOneWidget,
    );
  });

  testWidgets('the glyph is the spec size', (tester) async {
    await pump(tester);
    final theme = FcsTheme.light(AppLocale.ru).navigationBarTheme;
    final icon = theme.iconTheme!.resolve({})!;
    expect(icon.size, 19);
  });

  testWidgets('the label is 11px, and readable in both states', (tester) async {
    final theme = FcsTheme.light(AppLocale.ru).navigationBarTheme;
    final selected = theme.labelTextStyle!.resolve({WidgetState.selected})!;
    final idle = theme.labelTextStyle!.resolve({})!;

    expect(selected.fontSize, 11);
    expect(idle.fontSize, 11);

    // 11px is small text, so both states are held to the 4.5:1 that small text
    // needs — which is why the spec's own two colours are not used here.
    expect(contrastRatio(selected.color!, Ds.cream), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(idle.color!, Ds.cream), greaterThanOrEqualTo(4.5));
  });

  testWidgets('the active tab is named by colour, not by a pill', (tester) async {
    final theme = FcsTheme.light(AppLocale.ru).navigationBarTheme;
    // The spec has no indicator behind the active tab; Material draws one by
    // default, which would be an un-outlined surface in a system where every
    // surface is outlined.
    expect(theme.indicatorColor, Colors.transparent);

    final selected = theme.labelTextStyle!.resolve({WidgetState.selected})!;
    final idle = theme.labelTextStyle!.resolve({})!;
    expect(selected.color, isNot(idle.color));
    expect(selected.fontWeight!.value, greaterThan(idle.fontWeight!.value));
    // A variable font needs the axis set, not just fontWeight — otherwise the
    // renderer fakes the difference and both states look identical.
    expect(selected.fontVariations, contains(const FontVariation('wght', 800)));
    expect(idle.fontVariations, contains(const FontVariation('wght', 700)));
  });
}
