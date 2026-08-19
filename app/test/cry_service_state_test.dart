/// The 502/503 split — docs/TODO.md §9.13, frames 15a–15e.
///
/// Three situations used to render identically and all three ended with the
/// same invitation to record again:
///
///  * the analyser cannot analyse at all — production TODAY, because no
///    `model.pkl` has ever been trained (`docs/INTEGRATION_STATUS.md:34`), so
///    `packages/cry-classifier/app/main.py:95` answers 503;
///  * nothing reached the analyser — no signal, a dropped connection, a proxy
///    error;
///  * the clip reached it and could not be read.
///
/// Only the last two are worth another five seconds of a baby's voice. This
/// file pins which is which, and — the part that matters most — that the
/// microphone is never opened for the first one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/cry_classifier_client.dart';
import 'package:fcs_app/data/cry_recorder.dart';
import 'package:fcs_app/domain/cry_analysis.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/cry_insight_screen.dart';

const _en = L10n(AppLocale.en);
const _ru = L10n(AppLocale.ru);

const _okBody = '''
{"status":"success","primary_reason":"hungry","confidence":0.84,
 "probabilities":{"hungry":84,"tired":10,"belly_pain":4,"discomfort":2,"burping":0},
 "recommendation_ru":"Покормите малыша."}
''';

/// A recorder that counts. The count is the point of this file: a microphone
/// opened for a service that has already refused is the cost we are removing.
class _CountingRecorder implements CryRecorder {
  int starts = 0;
  final bool permission;
  _CountingRecorder({this.permission = true});

  @override
  Future<bool> start() async {
    starts++;
    return permission;
  }

  @override
  Future<List<int>?> stopAndRead() async => const [1, 2, 3];

  @override
  Future<void> dispose() async {}
}

/// Counts uploads too, so "no audio left the phone" is asserted, not assumed.
class _Uploads {
  int count = 0;
}

/// L10nScope ABOVE MaterialApp, not at `home:` — the `home:` form sits below
/// the Navigator and any pushed route silently falls back to English.
Widget _wrap(Widget child, {L10n l10n = _en}) =>
    L10nScope(l10n: l10n, child: MaterialApp(home: child));

CryClassifierClient _client({
  required bool available,
  CryFailure? uploadFails,
  _Uploads? uploads,
  int? probeStatus,
  Future<void>? probeGate,
}) =>
    CryClassifierClient(
      baseUrl: Uri.parse('http://test.local'),
      authToken: () async => 'tok',
      uploader: (url, bytes, name, headers) async {
        uploads?.count++;
        if (uploadFails != null) {
          throw CryClassifierException('stub', failure: uploadFails);
        }
        return _okBody;
      },
      prober: (url, headers) async {
        if (probeGate != null) await probeGate;
        return (status: probeStatus ?? 200, body: '{"available":$available}');
      },
    );

void main() {
  group('the status the proxy sends decides what she is told', () {
    // Pure mapping, no widgets: it is shared by the uploader and the screen and
    // must not drift between them.
    test('503 means the analyser cannot analyse', () {
      expect(cryFailureForStatus(503), CryFailure.unavailable);
    });

    test('400/413/415/422 are about the clip', () {
      for (final s in [400, 413, 415, 422]) {
        expect(cryFailureForStatus(s), CryFailure.unreadable, reason: 'status $s');
      }
    });

    test('a timeout or a rate limit is never blamed on her recording', () {
      // Sending her back to re-record because we were throttled is the same
      // defect as blaming the noise in her room for a missing model file.
      for (final s in [408, 429]) {
        expect(cryFailureForStatus(s), CryFailure.unreachable, reason: 'status $s');
      }
    });

    test('502/500 and anything else mean we never found out', () {
      for (final s in [500, 502, 504, 418]) {
        expect(cryFailureForStatus(s), CryFailure.unreachable, reason: 'status $s');
      }
    });
  });

  group('the analyser cannot answer', () {
    testWidgets('the microphone is never opened, and nothing is uploaded',
        (tester) async {
      final recorder = _CountingRecorder();
      final uploads = _Uploads();
      await tester.pumpWidget(_wrap(CryInsightScreen(
          recorder: recorder,
          client: _client(available: false, uploads: uploads))));
      await tester.pumpAndSettle();

      // The record control is gone — not greyed out, which would be a dead
      // control, and not still tappable, which would be the invitation.
      expect(find.text(_en.t('cry_record')), findsNothing);
      expect(find.text(_en.t('cry_again')), findsNothing);
      // The load-bearing assertions: absence of a widget can pass for the wrong
      // reason, a recorder that was never started cannot.
      expect(recorder.starts, 0, reason: 'the microphone was opened anyway');
      expect(uploads.count, 0, reason: 'audio was uploaded to a service that cannot answer');
    });

    testWidgets('it says so, and does not tell her to try again', (tester) async {
      await tester.pumpWidget(_wrap(
          CryInsightScreen(recorder: _CountingRecorder(), client: _client(available: false))));
      await tester.pumpAndSettle();

      expect(find.text(_en.t('cry_unavailable')), findsOneWidget);
      // The messages for the states she CAN act on must not be on screen: the
      // whole defect was that all three read the same.
      expect(find.text(_en.t('cry_error')), findsNothing);
      expect(find.text(_en.t('cry_not_sent')), findsNothing);
    });

    testWidgets('nothing was recorded, so it does not claim a clip was deleted',
        (tester) async {
      await tester.pumpWidget(_wrap(
          CryInsightScreen(recorder: _CountingRecorder(), client: _client(available: false))));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('cry_clip_deleted')), findsNothing);
    });

    testWidgets('«Проверить ещё раз» is a real control: it puts the button back',
        (tester) async {
      // A state with no way out is a dead end; a button that cannot change
      // anything is a dead control. This is the one action, and it works.
      var available = false;
      final recorder = _CountingRecorder();
      final client = CryClassifierClient(
        baseUrl: Uri.parse('http://test.local'),
        uploader: (url, bytes, name, headers) async => _okBody,
        prober: (url, headers) async => (status: 200, body: '{"available":$available}'),
      );
      await tester.pumpWidget(_wrap(CryInsightScreen(recorder: recorder, client: client), l10n: _ru));
      await tester.pumpAndSettle();
      expect(find.text(_ru.t('cry_record')), findsNothing);

      available = true; // the model finished training / the service came back
      await tester.tap(find.text(_ru.t('cry_recheck')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text(_ru.t('cry_unavailable')), findsNothing);
      expect(find.text(_ru.t('cry_record')), findsOneWidget,
          reason: 'the re-check could not bring the microphone back');
    });

    testWidgets('a 503 during the analysis latches, and repeats the deletion promise',
        (tester) async {
      // The other way into this state: the probe said yes, and the upload came
      // back 503 anyway. She DID record this time, so the clip promise is worth
      // repeating — and the next tap must not open the microphone again.
      final recorder = _CountingRecorder();
      final uploads = _Uploads();
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: recorder,
        client: _client(
            available: true, uploadFails: CryFailure.unavailable, uploads: uploads),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: cryRecordSeconds));
      await tester.pumpAndSettle();

      expect(recorder.starts, 1);
      expect(uploads.count, 1);
      expect(find.text(_en.t('cry_unavailable')), findsOneWidget);
      expect(find.text(_en.t('cry_clip_deleted')), findsOneWidget);
      // And the invitation is withdrawn, so she cannot spend a second recording
      // on the same guaranteed refusal.
      expect(find.text(_en.t('cry_again')), findsNothing);
      expect(find.text(_en.t('cry_record')), findsNothing);
    });
  });

  group('a failure she can act on', () {
    testWidgets('nothing reached the analyser: «не отправилось», not «не разобралось»',
        (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _CountingRecorder(),
        client: _client(available: true, uploadFails: CryFailure.unreachable),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: cryRecordSeconds));
      await tester.pumpAndSettle();

      expect(find.text(_en.t('cry_not_sent')), findsOneWidget);
      expect(find.text(_en.t('cry_unavailable')), findsNothing);
      // And she is still invited to try, because trying may well work.
      expect(find.text(_en.t('cry_again')), findsOneWidget);
    });

    testWidgets('an unreadable clip keeps the old message and the retry',
        (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _CountingRecorder(),
        client: _client(available: true, uploadFails: CryFailure.unreadable),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: cryRecordSeconds));
      await tester.pumpAndSettle();

      expect(find.text(_en.t('cry_error')), findsOneWidget);
      expect(find.text(_en.t('cry_unavailable')), findsNothing);
      expect(find.text(_en.t('cry_again')), findsOneWidget);
    });

    testWidgets('a transient failure does not latch: the next recording is allowed',
        (tester) async {
      final recorder = _CountingRecorder();
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: recorder,
        client: _client(available: true, uploadFails: CryFailure.unreachable),
      )));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text(_en.t(i == 0 ? 'cry_record' : 'cry_again')));
        await tester.pump();
        await tester.pump(const Duration(seconds: cryRecordSeconds));
        await tester.pumpAndSettle();
      }
      expect(recorder.starts, 2, reason: 'a blip stopped her from trying again');
    });
  });

  group('the probe itself', () {
    testWidgets('a probe we could not send leaves the recording on offer',
        (tester) async {
      // A lift with no signal is not evidence about the service. Refusing to
      // record here would invent a state.
      final recorder = _CountingRecorder();
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: recorder,
        // 502 from the proxy's own availability route: "we could not ask".
        client: _client(available: false, probeStatus: 502),
      )));
      await tester.pumpAndSettle();

      expect(find.text(_en.t('cry_unavailable')), findsNothing);
      expect(find.text(_en.t('cry_record')), findsOneWidget);
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: cryRecordSeconds));
      await tester.pumpAndSettle();
      expect(recorder.starts, 1);
      expect(find.text(_en.t('cry_result_title').toUpperCase()), findsOneWidget);
    });

    testWidgets('a tap before the probe answers waits for it, and still refuses',
        (tester) async {
      // The race: she taps the moment the screen opens. The microphone must
      // still not open for a service that is about to say no.
      final gate = Completer<void>();
      final recorder = _CountingRecorder();
      final uploads = _Uploads();
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: recorder,
        client: _client(
            available: false, uploads: uploads, probeGate: gate.future),
      )));
      await tester.pump();

      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump();
      // First, and on its own line: the microphone must not have opened while
      // the answer was still in flight. Asserted before the copy, so a failure
      // here names the defect rather than a missing label.
      expect(recorder.starts, 0,
          reason: 'the microphone opened before the probe had answered');
      // Not pumpAndSettle: the waiting state spins a CircularProgressIndicator,
      // which never settles.
      expect(find.text(_en.t('cry_checking')), findsWidgets,
          reason: 'the wait for the probe is not explained');

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text(_en.t('cry_unavailable')), findsOneWidget);
      expect(recorder.starts, 0, reason: 'the microphone opened while the probe was in flight');
      expect(uploads.count, 0);
    });

    testWidgets('the success path is untouched by any of this', (tester) async {
      CryAnalysis? saved;
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _CountingRecorder(),
        client: _client(available: true),
        onResult: (a) => saved = a,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: cryRecordSeconds));
      await tester.pumpAndSettle();

      expect(find.text(_en.t('cry_result_title').toUpperCase()), findsOneWidget);
      expect(find.text(_en.t('cry_reason_hungry')), findsWidgets);
      expect(find.text('Покормите малыша.'), findsOneWidget);
      expect(saved?.primaryReason, 'hungry');
      // None of the three failure strings is on a successful screen.
      for (final k in ['cry_error', 'cry_not_sent', 'cry_unavailable']) {
        expect(find.text(_en.t(k)), findsNothing, reason: k);
      }
    });
  });

  group('the wording', () {
    test('the unavailable message does not send her back to record', () {
      // §9.13: «Не "попробуйте ещё раз в тишине"». Retry advice is the whole
      // thing this state exists to withdraw.
      const retry = {
        AppLocale.ru: ['тишин', 'попробуйте ещё раз', 'запишите ещё'],
        AppLocale.kk: ['тыныштық', 'қайта жазыңыз'],
        AppLocale.en: ['quiet', 'try again', 'record again'],
      };
      for (final locale in AppLocale.values) {
        final text = L10n(locale).t('cry_unavailable').toLowerCase();
        for (final phrase in retry[locale]!) {
          expect(text.contains(phrase), isFalse,
              reason: '${locale.name} cry_unavailable still asks for another recording');
        }
      }
    });

    test('no failure string claims the audio is analysed on the phone', () {
      // Both claims are false and the published policy says the opposite in
      // three languages. cry_privacy_test pins cry_privacy; these are the new
      // strings, and they are the ones a mother reads when she is most likely
      // to wonder where the recording went.
      const banned = {
        // The exact claims docs/CLAUDE-app-design.md forbids. Not a bare «на
        // телефоне»: «на телефоне она не осталась» is the DELETION promise,
        // which is true, and banning the substring would ban the truth.
        AppLocale.ru: ['считается на телефоне', 'разбирается на телефоне', 'не уходит на сервер', 'без интернета'],
        AppLocale.kk: ['телефонда есептеледі', 'телефонда талданады', 'серверге кетпейді', 'интернетсіз'],
        AppLocale.en: ['analysed on your phone', 'never leaves', 'works offline'],
      };
      for (final locale in AppLocale.values) {
        for (final key in ['cry_unavailable', 'cry_not_sent', 'cry_checking']) {
          final text = L10n(locale).t(key).toLowerCase();
          for (final claim in banned[locale]!) {
            expect(text.contains(claim), isFalse, reason: '$key in ${locale.name} claims $claim');
          }
        }
      }
    });

    test('every new string is written in all three languages, kk never a copy of ru', () {
      for (final key in [
        'cry_unavailable',
        'cry_clip_deleted',
        'cry_not_sent',
        'cry_checking',
        'cry_recheck',
      ]) {
        for (final locale in AppLocale.values) {
          expect(L10n(locale).t(key).isNotEmpty, isTrue, reason: '$key missing in ${locale.name}');
        }
        expect(L10n(AppLocale.kk).t(key), isNot(L10n(AppLocale.ru).t(key)),
            reason: '$key: the Kazakh is the Russian');
      }
    });
  });
}
