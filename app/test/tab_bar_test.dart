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
library;

import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: DsTabBarSurface(
          child: NavigationBar(
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.favorite_outline), label: 'Здоровье'),
              NavigationDestination(icon: Icon(Icons.person_outline), label: 'Я'),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

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
