/// Widget test for the "Your baby this week" growth card on the child
/// development screen — the WHO weight/height range and the week's
/// motor/speech/cognition skills, from the shared baby-development calendar.
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/baby_development_repository.dart';
import 'package:fcs_app/domain/baby_development_content.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/child_development_screen.dart';

ChildDevCalendar _calendar() => const ChildDevCalendar(
      weeks: [
        ChildDevWeek(
          week: 24,
          weightKg: '6,1–9,3',
          heightCm: '61,8–70,1',
          ru: ChildDevSkills(motor: 'Учится переворачиваться.', speech: 'Тянется на руки.', cognition: 'Пробует всё на вкус.'),
          kk: ChildDevSkills(motor: 'Аунауды үйренуде.', speech: 'Қолын созады.', cognition: 'Бәрін дәмін татады.'),
        ),
        ChildDevWeek(
          week: 25,
          weightKg: '6,3–9,5',
          heightCm: '62,3–70,6',
          ru: ChildDevSkills(motor: 'Сидит с опорой.', speech: 'Лепечет слоги.', cognition: 'Ищет спрятанное.'),
          kk: ChildDevSkills(motor: 'Тіреумен отырады.', speech: 'Буындарды айтады.', cognition: 'Жасырынды іздейді.'),
        ),
      ],
      noteRu: 'Справочно.',
      noteKk: 'Анықтамалық.',
    );

Widget _wrap(Widget child) => L10nScope(l10n: L10n(AppLocale.en), child: child);

void main() {
  testWidgets('growth card shows the current week WHO range and skills', (tester) async {
    debugSetBabyDevelopment(_calendar());
    final today = DateTime(2026, 7, 23);
    final child = ChildProfile(
      id: 'c1',
      name: 'Alia',
      // ~24 weeks old → the week-24 calendar row.
      dateOfBirth: today.subtract(const Duration(days: 24 * 7)),
    );

    await tester.pumpWidget(MaterialApp(
      home: _wrap(ChildDevelopmentScreen(child: child, today: today)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Your baby this week'), findsOneWidget);
    expect(find.text('Week 24'), findsOneWidget);
    expect(find.textContaining('6,1–9,3'), findsOneWidget); // WHO weight range
    expect(find.textContaining('61,8–70,1'), findsOneWidget); // WHO height range
    expect(find.text('Учится переворачиваться.'), findsOneWidget); // en → ru fallback for skills
  });

  testWidgets('the growth card browses to the next week and back', (tester) async {
    debugSetBabyDevelopment(_calendar());
    final today = DateTime(2026, 7, 23);
    final child = ChildProfile(id: 'c1', name: 'Alia', dateOfBirth: today.subtract(const Duration(days: 24 * 7)));

    await tester.pumpWidget(MaterialApp(home: _wrap(ChildDevelopmentScreen(child: child, today: today))));
    await tester.pumpAndSettle();
    expect(find.text('Week 24'), findsOneWidget);
    expect(find.text('Back to current week'), findsNothing);

    // Next → week 25 content.
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Week 25'), findsOneWidget);
    expect(find.text('Сидит с опорой.'), findsOneWidget);
    expect(find.text('Back to current week'), findsOneWidget);

    // Back to current → week 24.
    await tester.tap(find.text('Back to current week'));
    await tester.pumpAndSettle();
    expect(find.text('Week 24'), findsOneWidget);
    expect(find.text('Back to current week'), findsNothing);
  });

  testWidgets('growth card is absent past the first year', (tester) async {
    debugSetBabyDevelopment(_calendar());
    final today = DateTime(2026, 7, 23);
    final toddler = ChildProfile(
      id: 'c2',
      name: 'Bek',
      dateOfBirth: DateTime(2024, 1, 1), // ~2.5 years
    );

    await tester.pumpWidget(MaterialApp(
      home: _wrap(ChildDevelopmentScreen(child: toddler, today: today)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Your baby this week'), findsNothing);
  });
}
