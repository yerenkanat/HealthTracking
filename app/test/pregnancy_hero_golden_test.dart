/// Renders the pregnancy hero to a PNG so it can be LOOKED at.
///
/// A widget test can assert that a number is on screen; it cannot tell you the
/// illustration is lopsided, the text sits on the artwork, or the third
/// trimester came out the same colour as the first. Goldens make the thing
/// visible without a device.
///
/// Run with `flutter test --update-goldens test/pregnancy_hero_golden_test.dart`
/// to regenerate after a deliberate change, and look at the result.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/ui/calendar/pregnancy_hero.dart';

/// A gestation at [week], derived the way the app derives it, so the golden
/// reflects real values rather than a hand-built struct.
GestationInfo at(int week) {
  final today = DateTime(2026, 7, 22);
  // Due date is 40 weeks after conception-start; week N means N weeks elapsed.
  final due = today.add(Duration(days: (40 - week) * 7));
  return gestationFor(due, today)!;
}

Widget frame(int week) => MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F5FA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PregnancyHero(
              gestation: at(week),
              weekLabel: '$week недель',
              remainingLabel: 'осталось ${(40 - week) * 7} дней',
              trimesterLabel: week < 13
                  ? 'первый триместр'
                  : week < 28
                      ? 'второй триместр'
                      : 'третий триместр',
              detailsLabel: 'Подробнее',
              onDetails: () {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the hero at three points in the pregnancy', (tester) async {
    // 1200x1000 at DPR 2 → 600x500 logical. The hero needs ~430 logical of
    // height; the first version of this gave it 390 and the overflow stripes
    // in the golden were the test frame, not the widget.
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // Three weeks side by side: the proportions and the palette must actually
    // differ, which is the whole reason the drawing is parametric.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F5FA),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in [8, 20, 36])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: PregnancyHero(
                      gestation: at(w),
                      weekLabel: '$w недель',
                      remainingLabel: 'осталось ${(40 - w) * 7} дней',
                      trimesterLabel: w < 13
                          ? 'первый триместр'
                          : w < 28
                              ? 'второй триместр'
                              : 'третий триместр',
                      detailsLabel: 'Подробнее',
                      onDetails: () {},
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ));
    // To REST: the breath is finite, so pumping past it gives a frame that
    // does not depend on when the shutter happened to open.
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Row).first,
      matchesGoldenFile('goldens/pregnancy_hero_weeks.png'),
    );
  });

  testWidgets('one hero, full width', (tester) async {
    tester.view.physicalSize = const Size(820, 1200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(frame(24));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PregnancyHero),
      matchesGoldenFile('goldens/pregnancy_hero_single.png'),
    );
  });
}
