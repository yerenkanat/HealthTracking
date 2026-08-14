/// The screening questionnaire, as a woman actually meets it.
///
/// `tool/verify_epds.dart` pins the arithmetic — the seven reverse-scored items
/// especially. What only a widget test can prove is that the SCREEN scores what
/// she tapped: that the option printed first on question 3 is worth three
/// points and the one printed first on question 1 is worth none, that item 10
/// sends her outward on a sheet that scores 1, and that the ten answers reach
/// the callback in no form at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/epds.dart';
import 'package:fcs_app/domain/postpartum.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/epds_screen.dart';
import 'package:fcs_app/ui/calendar/postpartum_screen.dart';
import 'package:fcs_app/ui/ds_widgets.dart';

final at = DateTime.utc(2026, 8, 12, 9, 30);

/// Every completed screening the screen handed back.
late List<EpdsResult> completed;

Future<void> pump(WidgetTester tester, [AppLocale loc = AppLocale.ru]) async {
  // Tall and wide: ten cards of four full-sentence options each.
  tester.view.physicalSize = const Size(1000, 12000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  completed = [];
  await tester.pumpWidget(L10nScope(
    l10n: L10n(loc),
    child: MaterialApp(
      home: EpdsScreen(
        // Keyed by locale so a second pump in the same test builds a NEW
        // State. Without it Flutter updates the existing element in place, the
        // answers and the result from the previous locale survive, and the
        // re-pumped screen opens on the result view with no questions on it.
        key: ValueKey(loc),
        onCompleted: completed.add,
        now: () => at,
        newId: () => 'fixed-id',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Tap option [option] (as printed, 0-based) of item [item] (1-based).
///
/// Scoped to the question's own card: «Да, иногда» is an option on four
/// different questions, so a bare find.text would be ambiguous — and, worse,
/// would silently answer the wrong one if it ever stopped being.
Future<void> answer(WidgetTester tester, L10n l, int item, int option) async {
  final card = find
      .ancestor(
        of: find.textContaining(l.t('epds_q$item')),
        matching: find.byType(DsCard),
      )
      .first;
  final target = find.descendant(of: card, matching: find.text(l.t('epds_q${item}_a$option')));
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

/// Fill the whole sheet with [option]-as-printed for every item.
Future<void> answerAll(WidgetTester tester, L10n l, int Function(int item) pick) async {
  for (var i = 1; i <= epdsItemCount; i++) {
    await answer(tester, l, i, pick(i));
  }
}

Future<void> submit(WidgetTester tester, L10n l) async {
  final button = find.text(l.t('epds_submit'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('all ten questions and forty options are on screen', (tester) async {
    await pump(tester);
    for (var i = 1; i <= epdsItemCount; i++) {
      expect(find.textContaining(ru.t('epds_q$i')), findsOneWidget, reason: 'q$i');
      for (var o = 0; o < epdsOptionCount; o++) {
        expect(find.text(ru.t('epds_q${i}_a$o')), findsWidgets, reason: 'q$i a$o');
      }
    }
  });

  testWidgets('it leads with what this is and is not', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('epds_disclaimer')), findsOneWidget);
    expect(find.text(ru.t('epds_instrument')), findsOneWidget);
    // And says the rendering is an aid, not a validated instrument.
    expect(find.text(ru.t('epds_not_validated')), findsOneWidget);
  });

  testWidgets('an unfinished sheet is not scored', (tester) async {
    await pump(tester);
    await answer(tester, ru, 1, 0);
    await submit(tester, ru);
    expect(find.text(ru.t('epds_incomplete')), findsOneWidget);
    expect(completed, isEmpty);
    // A blank is not a zero: nothing is saved and no result appears.
    expect(find.text(ru.t('epds_result_title')), findsNothing);
  });

  testWidgets('the calmest sheet scores 0 — the reverse-scored items included',
      (tester) async {
    // Forward items answered first-line, reverse items answered last-line.
    await pump(tester);
    await answerAll(tester, ru, (i) => isReverseScored(i) ? 3 : 0);
    await submit(tester, ru);

    expect(completed.single.score, 0);
    expect(find.text(ru.t('epds_score', {'n': 0})), findsOneWidget);
    expect(find.text(ru.t('epds_band_low')), findsOneWidget);
    // Nothing to send her anywhere.
    expect(find.byType(PostpartumWarningBlock), findsNothing);
  });

  testWidgets('answering the first line of every question scores 21, not 0',
      (tester) async {
    // The bug this whole file exists for. Seven questions print worst-first, so
    // "the top box" is three points on those — a screen that scored in printed
    // order would show 0 here and tell a woman in trouble she is fine.
    await pump(tester);
    await answerAll(tester, ru, (_) => 0);
    await submit(tester, ru);
    expect(completed.single.score, 21);
    expect(completed.single.band, EpdsBand.high);
  });

  testWidgets('a high total shows the outward block', (tester) async {
    await pump(tester);
    await answerAll(tester, ru, (_) => 0); // 21
    await submit(tester, ru);
    expect(find.text(ru.t('epds_band_high')), findsOneWidget);
    expect(find.byType(PostpartumWarningBlock), findsOneWidget);
    // The whole list, not a softened summary of it.
    for (final id in warningSigns) {
      expect(find.text(ru.t('pp_warn_$id')), findsOneWidget, reason: id);
    }
  });

  testWidgets('item 10 routes outward on a sheet that scores 1', (tester) async {
    // Calm everywhere, «почти никогда» on item 10 — one point, low band, and
    // she still needs a person today.
    await pump(tester);
    await answerAll(tester, ru, (i) => isReverseScored(i) ? 3 : 0);
    await answer(tester, ru, 10, 2);
    await submit(tester, ru);

    expect(completed.single.score, 1);
    expect(completed.single.band, EpdsBand.low);
    expect(find.text(ru.t('epds_harm_flag')), findsOneWidget);
    expect(find.byType(PostpartumWarningBlock), findsOneWidget);
    expect(find.text(ru.t('pp_warn_harm')), findsOneWidget);
  });

  testWidgets('«никогда» on item 10 does not raise the flag', (tester) async {
    await pump(tester);
    await answerAll(tester, ru, (i) => isReverseScored(i) ? 3 : 0);
    await submit(tester, ru);
    expect(find.text(ru.t('epds_harm_flag')), findsNothing);
  });

  testWidgets('the result hands back a date and a number, and nothing else',
      (tester) async {
    await pump(tester);
    await answerAll(tester, ru, (i) => isReverseScored(i) ? 2 : 1);
    await submit(tester, ru);

    final r = completed.single;
    expect(r.id, 'fixed-id');
    expect(r.takenAt, at);
    expect(r.toJson().keys.toSet(), {'id', 'takenAt', 'score', 'band'});
    // No answer, in any shape, reaches the caller.
    expect(r.toJson().toString(), isNot(contains('answer')));
    // And the screen says so.
    expect(find.text(ru.t('epds_saved')), findsOneWidget);
  });

  testWidgets('it never prints a diagnosis', (tester) async {
    await pump(tester);
    await answerAll(tester, ru, (_) => 0); // the highest sheet these taps make
    await submit(tester, ru);
    expect(find.textContaining('депресс'), findsNothing);
    expect(find.textContaining('диагноз'), findsNothing);
  });

  testWidgets('«пройти заново» clears the sheet rather than keeping her answers',
      (tester) async {
    await pump(tester);
    await answerAll(tester, ru, (_) => 0);
    await submit(tester, ru);
    expect(find.text(ru.t('epds_result_title')), findsOneWidget);

    await tester.tap(find.text(ru.t('epds_retake')));
    await tester.pumpAndSettle();
    expect(find.text(ru.t('epds_result_title')), findsNothing);
    expect(find.text(ru.t('epds_progress', {'n': 0})), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      final l = L10n(loc);
      await pump(tester, loc);
      await answerAll(tester, l, (_) => 0);
      await submit(tester, l);
      expect(find.textContaining('epds_'), findsNothing, reason: loc.name);
      expect(find.textContaining('pp_warn'), findsNothing, reason: loc.name);
    }
  });
}
