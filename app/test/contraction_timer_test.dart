/// Screen 10 — the contraction timer.
///
/// A golden would bless whatever it was shown, and `home_dashboard.png` was a
/// photograph of a defect that passed for a month. So almost nothing here is
/// pixels: it is the arithmetic, the ordering, the states, and the two promises
/// this screen makes out loud.
///
/// The two promises, both of which have to be TRUE and not merely printed:
///
///   * «Экран не гаснет» — the wakelock is actually taken, and released;
///   * the «пора в роддом» instruction is NOT on this screen, in any language,
///     because no clinical gate has ruled on it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/contraction.dart';
import 'package:fcs_app/domain/kick_session.dart' show formatElapsed;
import 'package:fcs_app/domain/labour_alert.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';

void main() {
  _arithmeticTests();
  _clinicalGateTests();
  _wakelockTests();
  _screenTests();
}

// ---------------------------------------------------------------------------
// 1 · THE ARITHMETIC, on hand-computed values.
//
// DateTime.now() is real wall-clock inside a widget test — pumping five minutes
// does not move it — so a four-minute interval can only be asserted on
// constructed data. That is why the ordering and the interval pairing were
// pulled out of the widget into [contractionRows].
// ---------------------------------------------------------------------------
void _arithmeticTests() {
  // 03:41, the time in the frame-10 reference row.
  final base = DateTime(2026, 8, 18, 3, 41);
  Contraction at(Duration after, int lastsSec) => Contraction(
        start: base.add(after),
        end: base.add(after).add(Duration(seconds: lastsSec)),
      );

  group('contractionRows', () {
    // c1 03:41 for 58s · c2 03:45:20 for 52s · c3 03:49 for 61s
    final list = [
      at(Duration.zero, 58),
      at(const Duration(minutes: 4, seconds: 20), 52),
      at(const Duration(minutes: 8), 61),
    ];

    test('is newest first', () {
      final rows = contractionRows(list);
      expect(rows.map((r) => r.start).toList(),
          [list[2].start, list[1].start, list[0].start],
          reason:
              'the log reads newest-first — she is looking for the last one');
    });

    test('pairs each row with the gap from the PREVIOUS start', () {
      final rows = contractionRows(list);
      // Newest row: 03:49 minus 03:45:20 = 3:40.
      expect(rows[0].interval, const Duration(minutes: 3, seconds: 40));
      // Middle row: 03:45:20 minus 03:41 = 4:20 — the reference row exactly.
      expect(rows[1].interval, const Duration(minutes: 4, seconds: 20));
      expect(formatElapsed(rows[1].interval!), '4:20');
    });

    test('the first contraction of a session has NO interval', () {
      // Not Duration.zero. There is no earlier start to measure from, and a
      // zero would render as a measured gap of nothing.
      expect(contractionRows(list).last.interval, isNull);
      expect(contractionRows([list.first]).single.interval, isNull);
    });

    test('carries each row its own duration, not its neighbour', () {
      final rows = contractionRows(list);
      expect(formatElapsed(rows[0].duration), '1:01');
      expect(formatElapsed(rows[1].duration), '0:52');
      expect(formatElapsed(rows[2].duration), '0:58');
    });

    test('is empty for an empty session', () {
      expect(contractionRows(const []), isEmpty);
    });
  });

  test('hhmm is zero-padded 24-hour, not a locale time format', () {
    // It gets read down a telephone to a maternity unit. «3:41 AM» under a
    // locale the app did not hand it is the trap this avoids.
    expect(hhmm(DateTime(2026, 8, 18, 3, 41)), '03:41');
    expect(hhmm(DateTime(2026, 8, 18, 23, 5)), '23:05');
  });

  // The checklist may only tick a criterion the timed pattern ACTUALLY meets.
  group('fiveOneOneProgress ticks only what is met', () {
    final now = DateTime(2026, 8, 18, 4, 0);
    List<Contraction> every5min(int count, int lastsSec, int firstMinutesAgo) {
      final out = <Contraction>[];
      for (var i = 0; i < count; i++) {
        final s = now.subtract(Duration(minutes: firstMinutesAgo - i * 5));
        out.add(Contraction(start: s, end: s.add(Duration(seconds: lastsSec))));
      }
      return out;
    }

    test('all three, for a full hour of minute-long contractions 5 min apart',
        () {
      // 12 contractions from 58 minutes ago to 3 minutes ago — span 55 min.
      final p = fiveOneOneProgress(every5min(12, 60, 58), now: now);
      expect(p.intervalMet, isTrue);
      expect(p.durationMet, isTrue);
      expect(p.sustainedMet, isTrue);
      expect(p.metCount, 3);
    });

    test('short contractions do NOT tick the duration criterion', () {
      final p = fiveOneOneProgress(every5min(12, 30, 58), now: now);
      expect(p.durationMet, isFalse, reason: '30s is not "about a minute"');
      expect(p.intervalMet, isTrue);
      expect(p.metCount, 2);
    });

    test('half an hour does NOT tick sustained', () {
      // 6 contractions spanning 25 minutes: the right shape, not yet the hour.
      final p = fiveOneOneProgress(every5min(6, 60, 25), now: now);
      expect(p.sustainedMet, isFalse);
      expect(p.metCount, 2);
    });

    test('two contractions an hour apart tick almost nothing', () {
      // The documented anti-case: this spanned an hour, so a span-only rule
      // called it sustained for someone not in labour at all.
      final p = fiveOneOneProgress([
        Contraction(
            start: now.subtract(const Duration(minutes: 60)),
            end: now.subtract(const Duration(minutes: 59))),
        Contraction(start: now, end: now.add(const Duration(minutes: 1))),
      ], now: now);
      expect(p.sustainedMet, isFalse);
      expect(p.intervalMet, isFalse);
      expect(p.metCount, 1);
    });

    test('nothing is met for an empty session', () {
      expect(fiveOneOneProgress(const [], now: now).metCount, 0);
    });
  });
}

// ---------------------------------------------------------------------------
// 2 · THE CLINICAL GATE.
//
// «Схватки по минуте каждые 5 минут в течение часа — пора ехать в роддом» is a
// medical instruction: it tells a woman in labour when to leave her house.
// docs/CLINICAL-REVIEW-WATCH.md carries NO ruling on contractions — it covers
// heart rate, SpO2, blood pressure, temperature and glucose and says nothing
// about labour. So the sentence is unreviewed, and unreviewed medical copy does
// not ship on a designer's judgement.
// ---------------------------------------------------------------------------
void _clinicalGateTests() {
  group('the go-to-hospital directive is behind the gate', () {
    test('its copy key is null, so the card cannot render', () {
      expect(labourAlertBodyKey, isNull,
          reason:
              'Setting this is a CLINICAL decision, not an engineering one. '
              'It needs a verdict in docs/CLINICAL-REVIEW-WATCH.md naming the '
              'wording in ru + kk + en AND the threshold, plus a fingerprint in '
              'reviewed_medical_copy_test.dart. See domain/labour_alert.dart.');
    });

    test('stays silent even when all three criteria are met', () {
      // The strongest input the screen can produce. It still shows nothing.
      const allMet = FivOneOneProgress(true, true, true);
      expect(allMet.allMet, isTrue);
      expect(showLabourAlert(allMet), isFalse,
          reason: 'the pattern being met is NOT sufficient — the copy must be '
              'reviewed first');
    });

    // The fragments below are the THRESHOLD CLAUSE, not the word «роддом».
    //
    // The first version of this test banned «роддом» and «перзентхана» and
    // failed on eight innocent strings: «Сумка в роддом», «В роддоме» on the
    // vaccination card, «Схватки, воды и когда ехать в роддом». Those are
    // ordinary vocabulary in a pregnancy app. A deny-list that cries wolf is
    // how the list stops being believed — `refused_sentences_test` records the
    // same lesson about «круглосуточно».
    //
    // What makes the refused sentence refused is the NUMBER attached to an
    // instruction: "a minute long, every five minutes, for an hour — go". The
    // checklist may say «Интервал около 5 минут» as a description of her own
    // data; nothing may say «каждые 5 минут … пора».
    const forbidden = {
      'каждые 5 минут': 'ru — the 5-1-1 frequency clause as an instruction',
      'каждые пять минут': 'ru — the same, spelled out',
      'пора в роддом': 'ru — the directive itself',
      'пора ехать': 'ru — the directive, without the destination',
      'әр 5 минут сайын': 'kk — the 5-1-1 frequency clause',
      'every 5 minutes for an hour': 'en — the same clause',
    };

    List<String> scan() {
      final hits = <String>[];
      for (final key in allL10nKeys) {
        for (final locale in AppLocale.values) {
          final text = L10n(locale).t(key).toLowerCase();
          forbidden.forEach((frag, why) {
            if (text.contains(frag)) hits.add('$key [$locale] «$frag» — $why');
          });
        }
      }
      return hits;
    }

    /// WHERE THE CLAUSE ALREADY IS, and why this is a pin and not an exclusion.
    ///
    /// Writing this test turned up the sentence already shipping — not on the
    /// timer, but on `LabourSignsScreen`, which the timer's own info icon opens.
    /// `lab_go_five_one_one` states the rule in ru and kk inside a «when to go
    /// in» list. When this was written the `lab_*` keys were NOT matched by
    /// `isMedicalKey` in reviewed_medical_copy_test.dart, so they carried no
    /// fingerprint at all. That hole was closed on 2026-08-18 (TODO §8.8): the
    /// whole `lab_` prefix is now matched and every key in it is fingerprinted.
    ///
    /// `knownUnreviewed` still says what it says, because PINNING IS NOT
    /// APPROVING. The text is frozen; no reviewer has yet ruled on it.
    ///
    /// That is not mine to delete — the guide is a deliberate, spec'd feature
    /// and removing clinical content is as much a clinical decision as adding
    /// it. So the exposure is PINNED here, by exact key, which is strictly
    /// stronger than excluding it:
    ///
    ///   * a NEW key acquiring the clause fails the test;
    ///   * these keys being fixed ALSO fails it, so the list cannot go stale
    ///     and quietly outlive the problem it records.
    ///
    /// Tracked in docs/TODO.md §8 as an open question for the gate.
    const knownUnreviewed = {'lab_intro', 'lab_go_five_one_one'};

    test('the instruction is on no NEW screen, and the old one has not grown',
        () {
      // Kept OUT of l10n.dart for this screen rather than added behind a flag:
      // a string in the catalogue is one `if` away from a screen; a string that
      // does not exist is not.
      final keys = scan().map((h) => h.split(' ').first).toSet();
      expect(keys, knownUnreviewed,
          reason: 'The 5-1-1 threshold clause moved.\n'
              '${scan().join('\n')}\n\n'
              'If a key was ADDED: this sentence tells a woman in labour when '
              'to leave her house, and it goes through the clinical gate '
              'first — see app/lib/domain/labour_alert.dart.\n'
              'If a key was REMOVED or fixed: good — update knownUnreviewed '
              'and close the item in docs/TODO.md §8.');
    });

    test('no contraction-timer string carries the clause', () {
      // The narrower claim this screen is actually responsible for.
      final onThisScreen =
          scan().where((h) => h.startsWith('contr_')).toList();
      expect(onThisScreen, isEmpty,
          reason: 'The timer must not state a threshold for going in.');
    });

    test('the matcher would actually catch the sentence, and spares the rest',
        () {
      // Non-vacuity in both directions, because a deny-list has two failure
      // modes and only one of them is loud.
      const wouldBeRefused =
          'Схватки по минуте каждые 5 минут в течение часа — пора ехать в роддом';
      final caught = forbidden.keys
          .where((f) => wouldBeRefused.toLowerCase().contains(f))
          .toList();
      expect(caught, isNotEmpty,
          reason: 'the deny-list does not match the sentence it exists for');

      // …and the innocent neighbours it must NOT flag.
      for (final key in ['bag_title', 'vac_at_birth', 'contr_511_interval']) {
        for (final locale in AppLocale.values) {
          final text = L10n(locale).t(key).toLowerCase();
          for (final frag in forbidden.keys) {
            expect(text.contains(frag), isFalse,
                reason: '$key [$locale] is ordinary vocabulary, not the '
                    'directive — the list must not fire on it');
          }
        }
      }
    });

    test('the checklist that DOES ship instructs nothing', () {
      // What ships instead: her own timings reflected back, under a disclaimer.
      for (final locale in AppLocale.values) {
        expect(L10n(locale).t('contr_511_note'), isNotEmpty);
      }
      expect(const L10n(AppLocale.ru).t('contr_511_note'),
          contains('не медицинский совет'));
      expect(const L10n(AppLocale.ru).t('contr_511_note'),
          contains('своего врача'));
    });

    test('the matcher actually reads the catalogue', () {
      // Non-vacuity: without this the scan above passes when allL10nKeys is
      // empty or t() starts returning keys — a green tick asserting nothing.
      expect(allL10nKeys.length, greaterThan(500));
      expect(const L10n(AppLocale.ru).t('contr_title'), 'Схватки');
    });
  });
}

// ---------------------------------------------------------------------------
// 3 · «ЭКРАН НЕ ГАСНЕТ» — the promise, and whether the code keeps it.
// ---------------------------------------------------------------------------
void _wakelockTests() {
  testWidgets('holds the screen awake while it is open', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: ContractionTimerScreen(keepAwake: (on) async => calls.add(on)),
      ),
    ));
    expect(calls, [true]);
  });

  testWidgets('lets it sleep again on the way out', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: ContractionTimerScreen(keepAwake: (on) async => calls.add(on)),
      ),
    ));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(calls, [true, false]);
  });

  testWidgets('releases it even when nothing was recorded', (tester) async {
    // Leaving the wakelock on because the session was empty would flatten the
    // battery of a phone she is relying on to call somebody.
    final calls = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: ContractionTimerScreen(
          keepAwake: (on) async => calls.add(on),
          onSave: (_, __, ___) {},
        ),
      ),
    ));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(calls.last, false);
  });

  testWidgets('BOTH halves of the printed promise are true', (tester) async {
    // The sentence says the screen stays awake AND stays dark. It does not say
    // "dimmed" — there is no brightness plugin in pubspec.yaml, and a promise
    // the code does not keep is the defect class this repo has been clearing.
    final calls = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: ContractionTimerScreen(keepAwake: (on) async => calls.add(on)),
      ),
    ));

    // It is printed…
    expect(
        find.text('The screen stays awake and dark while the timer is open.'),
        findsOneWidget);
    // …the wakelock half is kept…
    expect(calls, [true],
        reason: 'the sentence claims a wakelock that is taken');
    // …and the dark half is kept, on the Scaffold itself.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Ds.nightBg,
        reason: 'the sentence claims a dark canvas — §2.17');

    // And it never claims brightness control, which nothing here implements.
    for (final locale in AppLocale.values) {
      final s = L10n(locale).t('contr_awake_note').toLowerCase();
      expect(s.contains('яркост'), isFalse);
      expect(s.contains('приглуш'), isFalse);
      expect(s.contains('dim'), isFalse);
    }
  });
}

// ---------------------------------------------------------------------------
// 4 · THE SCREEN — hierarchy, states, and the frame-10 furniture.
// ---------------------------------------------------------------------------
void _screenTests() {
  Widget wrap(
          {VoidCallback? onOpenHistory,
          void Function(int, Duration, Duration)? onSave}) =>
      MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: ContractionTimerScreen(
              onOpenHistory: onOpenHistory, onSave: onSave),
        ),
      );

  Future<void> record(WidgetTester tester) async {
    await tester.tap(find.text('Contraction started'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Contraction ended'));
    await tester.pump();
  }

  testWidgets('first run: empty state, and the button invites the first tap',
      (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('No contractions recorded yet.'), findsOneWidget);
    expect(find.text('Contraction started'), findsOneWidget);
    expect(find.text('Tap when a contraction begins.'), findsOneWidget);
    // Nothing to reset, nothing to average, no log header.
    expect(find.text('Recent contractions'), findsNothing);
    expect(find.text('Total'), findsNothing);
  });

  testWidgets('while a contraction runs, the headline says so', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.text('Contraction started'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Contraction in progress'), findsOneWidget);
    // The button is now the one from the frame, and its second line changes.
    expect(find.text('Contraction ended'), findsOneWidget);
    expect(find.text('Tap when it eases off'), findsOneWidget);
    // The empty state is gone — a running contraction is not "nothing yet".
    expect(find.text('No contractions recorded yet.'), findsNothing);
  });

  testWidgets('between contractions the headline switches to the rest timer',
      (tester) async {
    await tester.pumpWidget(wrap());
    await record(tester);
    expect(find.text('Between contractions'), findsOneWidget);
    expect(find.text('Contraction in progress'), findsNothing);
    // Back to the start label.
    expect(find.text('Contraction started'), findsOneWidget);
  });

  testWidgets(
      'one contraction: the log appears, averages refuse to invent an interval',
      (tester) async {
    await tester.pumpWidget(wrap());
    await record(tester);

    expect(find.text('Recent contractions'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    // The row says «first», not an interval of zero.
    expect(find.text('first'), findsOneWidget);
    // And the average-interval stat is an em dash, not 0:00 — there is no gap
    // to average with one contraction.
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('the 5-1-1 checklist arrives on the second contraction',
      (tester) async {
    await tester.pumpWidget(wrap());
    await record(tester);
    expect(find.text('5-1-1 pattern'), findsNothing);

    await record(tester);
    expect(find.text('5-1-1 pattern'), findsOneWidget);
    expect(find.textContaining('not medical advice'), findsOneWidget);
    // Two seconds apart and a second long: none of the three criteria is met,
    // and the card must say 0/3 rather than flatter the pattern.
    expect(find.text('0/3'), findsOneWidget);
  });

  testWidgets('the log is newest-first on screen', (tester) async {
    // A taller viewport than the 800x600 default: with the live card, the
    // 5-1-1 card and the stats bar above it, the second row falls outside a
    // 600px surface and the finder reports "0 widgets" rather than a wrong
    // order. Both rows have to be laid out for their order to mean anything.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await record(tester);
    await record(tester);

    // Anchored, because the 5-1-1 criterion «About 5 minutes apart» sits above
    // the log and a loose `textContaining('apart')` matches it too — which
    // would have compared the checklist against a row and "passed" for a
    // reason that has nothing to do with ordering.
    final intervalRow = find.textContaining(RegExp(r'^\d+:\d\d apart$'));
    expect(intervalRow, findsOneWidget,
        reason: 'exactly one of the two rows has an interval');

    // «first» marks contraction #1, which must sit BELOW the newer row.
    final firstRowY = tester.getTopLeft(find.text('first')).dy;
    final apartY = tester.getTopLeft(intervalRow).dy;
    expect(apartY, lessThan(firstRowY),
        reason: 'the newer contraction (which has an interval) is drawn above '
            'the first one');
  });

  testWidgets('History renders only when there is somewhere to go',
      (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('History'), findsNothing,
        reason: 'no callback — a dead control is worse than none');

    var opened = false;
    await tester.pumpWidget(wrap(onOpenHistory: () => opened = true));
    expect(find.text('History'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('reset lives on the log header and confirms before erasing',
      (tester) async {
    await tester.pumpWidget(wrap());
    await record(tester);

    // It is NOT in the app bar next to navigation any more.
    expect(find.byIcon(Icons.restart_alt_rounded), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Reset contractions?'), findsOneWidget);
    expect(find.text('The recorded contractions will be cleared.'),
        findsOneWidget);

    await tester.tap(find.text('Reset').last);
    await tester.pumpAndSettle();
    expect(find.text('No contractions recorded yet.'), findsOneWidget);
    expect(find.text('Recent contractions'), findsNothing);
  });

  testWidgets('recorded contractions are handed over on close', (tester) async {
    int? savedCount;
    await tester.pumpWidget(wrap(onSave: (count, _, __) => savedCount = count));
    await record(tester);
    await record(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(savedCount, 2);
  });

  testWidgets('a reset session is NOT saved on close', (tester) async {
    int? savedCount;
    await tester.pumpWidget(wrap(onSave: (count, _, __) => savedCount = count));
    await record(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset').last);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(savedCount, isNull);
  });

  testWidgets('the primary action sits in the bottom bar, not the body',
      (tester) async {
    // ЧАСТЬ 4 rule 8: «действие в нижней трети». She taps this over and over,
    // one-handed, through labour.
    await tester.pumpWidget(wrap());
    final barY = tester.getTopLeft(find.byType(DsBottomActionBar)).dy;
    final screenH = tester.getSize(find.byType(Scaffold)).height;
    expect(barY, greaterThan(screenH * 2 / 3),
        reason: 'the repeated action must be under the resting thumb');
  });
}
