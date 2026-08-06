/// Guards UI checklist §4: interactive targets must be at least 48x48 dp.
///
/// These measure the RENDERED size of specific controls that were previously
/// too small (a 20dp text link is easy to ship and easy to miss by eye), so a
/// future layout tweak can't quietly shrink them again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/course_lesson.dart';
import 'package:fcs_app/domain/weight.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/weight_card.dart';
import 'package:fcs_app/ui/content/mama_course_screen.dart';
import 'package:fcs_app/ui/dashboard/water_card.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/theme.dart';

const _minTarget = 48.0;

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: Scaffold(body: ListView(children: [child])),
        ),
      );

  /// Height of the InkWell wrapping [label].
  double tapHeightOf(WidgetTester tester, String label) {
    final target = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
    return tester.getSize(target).height;
  }

  testWidgets('weight card target row is a full tap target', (tester) async {
    const entries = [
      WeightEntry(date: '2026-07-01', kg: 62.0),
      WeightEntry(date: '2026-07-15', kg: 63.4),
    ];
    await tester.pumpWidget(wrap(WeightCard(entries: entries, onLog: (_) {}, onSetGoal: (_) {})));
    expect(tapHeightOf(tester, '+ Set a weight target'), greaterThanOrEqualTo(_minTarget));
  });

  testWidgets('water card goal link is a full tap target', (tester) async {
    await tester.pumpWidget(wrap(WaterCard(
      count: 3,
      goal: 8,
      onAdd: () {},
      onRemove: () {},
      onSetGoal: (_) {},
    )));
    expect(tapHeightOf(tester, '3 of 8 glasses'), greaterThanOrEqualTo(_minTarget));
  });

  /// The course list's "Continue" button.
  ///
  /// Shipped at 46dp. Two under the minimum is invisible by eye and exactly the
  /// kind of thing this file exists for — and this is the one button the course
  /// is meant to be driven from, tapped by somebody holding a baby.
  testWidgets('the course continue button clears 48dp', (tester) async {
    final lessons = [
      const CourseLesson(id: 'a', titleRu: 'Первые дни', youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ', sort: 10),
    ];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: MamaCourseScreen(access: CourseAccess(entitled: true, lessons: lessons)),
      ),
    ));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byKey(const Key('course-continue')));
    expect(size.height, greaterThanOrEqualTo(_minTarget));
  });

  _dsControls();
}

/// The design-system controls.
///
/// DsToggle draws a 48x28 pill because the spec specifies that shape, and 28dp
/// is not a tap target. The Material Switch it replaced padded itself out to
/// 48; adopting DsToggle on the settings notification row and nine reminder
/// rows shrank the target on all ten without changing anything visible.
///
/// Caught by running the UI checklist over the converted screens rather than by
/// any test — which is why it is a test now.
void _dsControls() {
  testWidgets('DsToggle is tappable at 48dp even though it draws 28',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.en),
      home: Scaffold(body: Center(child: DsToggle(value: true, onChanged: (_) {}))),
    ));
    await tester.pumpAndSettle();

    final tap = tester.getSize(
      find.descendant(of: find.byType(DsToggle), matching: find.byType(InkWell)).first,
    );
    expect(tap.height, greaterThanOrEqualTo(_minTarget),
        reason: 'the hit area must clear 48dp');
    expect(tap.width, greaterThanOrEqualTo(_minTarget));

    // …and the pill itself still draws at the spec's size.
    final pill = tester.widgetList<AnimatedContainer>(
      find.descendant(of: find.byType(DsToggle), matching: find.byType(AnimatedContainer)),
    ).first;
    expect((pill.constraints?.maxHeight ?? 28), 28);
  });
}
