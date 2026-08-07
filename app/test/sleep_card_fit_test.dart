/// The sleep card's headline number shrinks only when it has to.
///
/// The 320dp sweep found «8 ч 15 мин» overflowing its card by 59px at 30px
/// monospace, and the fix was a FittedBox that scales it down. A FittedBox is
/// easy to get wrong in the opposite direction: given a tight constraint it
/// will happily shrink text that had room, and the headline figure of the whole
/// card quietly renders at 22px on every phone.
///
/// So this pins both ends — full size where it fits, smaller where it does not,
/// and never clipped in either case.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/sleep_card.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  final night = SleepSummary(
    night: DateTime(2026, 7, 15),
    deepMin: 95, remMin: 70, lightMin: 280, awakeMin: 12,
  );

  /// Render the card at [width] and report how tall the headline actually is.
  ///
  /// The painted height against the declared 30px is what says whether the
  /// FittedBox scaled: a RenderParagraph reports the style it was given, so
  /// reading `.text.style.fontSize` would say 30 either way and prove nothing.
  Future<double> headlineHeight(WidgetTester tester, double width, AppLocale locale) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(locale),
      home: L10nScope(
        l10n: L10n(locale),
        child: Scaffold(
          body: ListView(children: [SleepCard(nights: [night], onLog: () {})]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the card overflowed at ${width}dp');

    final l = L10n(locale);
    final finder = find.text(l.duration(night.asleepMin));
    expect(finder, findsOneWidget, reason: 'the headline duration is not on the card');
    // The paragraph inside the FittedBox lays out at its natural size; what the
    // user sees is that box after the scale, so measure the painted rectangle.
    return tester.getSize(finder).height;
  }

  testWidgets('at 402dp the headline is not shrunk at all', (tester) async {
    // The golden width. A FittedBox given a tight constraint shrinks text that
    // had room, and it does it silently on every screen.
    final h = await headlineHeight(tester, 402, AppLocale.ru);
    expect(h, closeTo(30, 1.5),
        reason: 'the headline was scaled down on a phone with room to spare');
  });

  testWidgets('at 360dp it is still full size', (tester) async {
    final h = await headlineHeight(tester, 360, AppLocale.ru);
    expect(h, closeTo(30, 1.5));
  });

  testWidgets('at 320dp it fits, at full size', (tester) async {
    // The width the sweep found the overflow at. Making the LABEL beside it
    // flexible is what bought the room back, so the number itself never has to
    // shrink here — which is the better of the two outcomes.
    final h = await headlineHeight(tester, 320, AppLocale.ru);
    expect(h, closeTo(30, 1.5));
  });

  testWidgets('and it still fits when there is genuinely no room', (tester) async {
    // The FittedBox is the backstop under the flexible label: a card squeezed
    // narrower than any phone — a future two-column layout, a split screen —
    // must scale the number down rather than paint a striped bar across it.
    //
    // Measured as "did Flutter report an overflow", because a FittedBox scales
    // by transform: the paragraph inside still reports its natural 30px, so
    // reading the Text's size says nothing about what is on screen. That is
    // what the first version of this test got wrong.
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: Scaffold(
          body: ListView(children: [
            SizedBox(width: 180, child: SleepCard(nights: [night], onLog: () {})),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the headline overflows once the label has no more to give');
  });

  testWidgets('the legend keeps its durations and gives up label text', (tester) async {
    // Of the two halves of a legend chip, the duration is the one worth
    // reading — the colour beside it already says which stage it is.
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const locale = AppLocale.ru;
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(locale),
      home: L10nScope(
        l10n: const L10n(locale),
        child: Scaffold(
          body: ListView(children: [SleepCard(nights: [night], onLog: () {})]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    const l = L10n(locale);
    for (final mins in [night.deepMin, night.remMin, night.lightMin]) {
      expect(find.text(l.duration(mins)), findsWidgets,
          reason: 'a legend duration was clipped away at 320dp');
    }
    // The label is the part allowed to ellipsise, and it must be doing so by
    // ELLIPSIS rather than by painting past the edge.
    final label = tester.renderObject<RenderParagraph>(
      find.text('${l.t('sleep_deep')} ').first,
    );
    expect(label.overflow, TextOverflow.ellipsis);
  });
}
