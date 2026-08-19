/// Where the recording goes is said BEFORE the microphone opens.
///
/// This is the only screen in the app that captures audio — five seconds
/// recorded inside somebody's home, of their baby — and the privacy policy
/// listed chat messages and band readings and said nothing about it at all.
///
/// docs/CLAUDE-app-design.md asks for more than disclosure: «Плач разбирается
/// на телефоне, записи не уходят на сервер.» That is an on-device inference
/// build. Until it exists the app must not imply it, and must say plainly what
/// it actually does — which the server side is held to in
/// packages/backend cryNotStored.test.ts.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/cry_classifier_client.dart';
import 'package:fcs_app/data/cry_recorder.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/cry_insight_screen.dart';

/// Never touches hardware or a socket. This file is about what the screen SAYS
/// before anything is recorded, not about recording.
class _StubRecorder implements CryRecorder {
  @override
  Future<bool> start() async => true;
  @override
  Future<List<int>?> stopAndRead() async => const [1, 2, 3];
  @override
  Future<void> dispose() async {}
}

CryClassifierClient _stubClient() => CryClassifierClient(
      baseUrl: Uri.parse('http://stub.local'),
      authToken: () async => 'tok',
      uploader: (url, bytes, name, headers) async =>
          '{"reason":"hunger","confidence":0.8}',
      // The availability probe the screen fires before it opens a microphone.
      // Answered explicitly so this test drives a KNOWN state rather than
      // whatever flutter_test's HTTP stub happens to return.
      prober: (url, headers) async => (status: 200, body: '{"available":true}'),
    );

void main() {
  Future<void> open(WidgetTester tester, AppLocale locale) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: L10n(locale),
        child: CryInsightScreen(
          recorder: _StubRecorder(),
          client: _stubClient(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the screen says where the audio goes, in every language', (tester) async {
    for (final locale in AppLocale.values) {
      await open(tester, locale);
      final l = L10n(locale);
      expect(find.text(l.t('cry_privacy')), findsOneWidget,
          reason: 'no privacy line on the recording screen in ${locale.name}');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('it is above the record button, not below the result', (tester) async {
    // Consent that arrives after the recording is not consent. A line under the
    // answer is a line she reads once the audio has already been sent.
    await open(tester, AppLocale.ru);
    const l = L10n(AppLocale.ru);
    final noteY = tester.getTopLeft(find.text(l.t('cry_privacy'))).dy;
    final buttonY = tester.getTopLeft(find.byType(GestureDetector).first).dy;
    expect(noteY, lessThan(buttonY),
        reason: 'the privacy line sits below the microphone button');
  });

  group('the wording matches what the code does', () {
    test('it does not claim the audio stays on the phone', () {
      // The spec wants that; the build does not do it yet. Claiming it would be
      // the worst of the three options — a promise the network contradicts.
      for (final locale in AppLocale.values) {
        final text = L10n(locale).t('cry_privacy').toLowerCase();
        for (final claim in ['на телефоне', 'не уходит', 'on your phone', 'never leaves']) {
          expect(text.contains(claim), isFalse,
              reason: '${locale.name} claims on-device analysis, which is not what happens');
        }
      }
    });

    test('it says both halves: it is sent, and it is not kept', () {
      // Either half alone is misleading. "Sent to our server" with no retention
      // answer reads worse than the truth; "not stored" without "sent" reads
      // like it never left.
      const sent = {AppLocale.ru: 'сервер', AppLocale.kk: 'сервер', AppLocale.en: 'server'};
      const kept = {AppLocale.ru: 'не сохраня', AppLocale.kk: 'сақталмайды', AppLocale.en: 'not stored'};
      for (final locale in AppLocale.values) {
        final text = L10n(locale).t('cry_privacy').toLowerCase();
        expect(text, contains(sent[locale]!), reason: '${locale.name} does not say where it goes');
        expect(text, contains(kept[locale]!), reason: '${locale.name} does not say it is not kept');
      }
    });

    test('the failure message does not blame the room, and says the clip is gone', () {
      // The one error this screen can show is, in production today, almost
      // always the same one: there is no trained model.pkl, the classifier
      // answers 503 and the proxy turns it into 502. The copy used to read
      // «Попробуйте ещё раз в тишине» — advice about NOISE, for a failure that
      // is not about noise. It blamed a mother's room for a missing file on our
      // server and invited her to upload her baby's cry again, and again.
      //
      // «В тишине» is the right advice for a low-confidence ANSWER, and now
      // lives only in cry_unsure_body, where it is true.
      const quiet = {AppLocale.ru: 'тишин', AppLocale.kk: 'тыныштық', AppLocale.en: 'quiet'};
      // And this is the moment she is most likely to wonder what happened to
      // the recording, so the failure message repeats the deletion promise —
      // which the three filesystem tests below prove is true on this exact
      // branch: the clip is deleted in a `finally` BEFORE the upload can fail.
      const gone = {AppLocale.ru: 'не осталась', AppLocale.kk: 'қалмады', AppLocale.en: 'nothing is left'};
      for (final locale in AppLocale.values) {
        final text = L10n(locale).t('cry_error').toLowerCase();
        expect(text.contains(quiet[locale]!), isFalse,
            reason: '${locale.name} still blames the noise in her room for a server that has no model');
        expect(text, contains(gone[locale]!),
            reason: '${locale.name} does not say the recording is gone');
      }
    });

    test('the privacy policy lists the recording too', () {
      // It named chat messages and band readings and omitted the one piece of
      // audio — the most sensitive thing the app sends anywhere. The rewritten
      // policy gives it a section of its own, so this now pins that section.
      const cry = {AppLocale.ru: 'плач', AppLocale.kk: 'жылау', AppLocale.en: 'cry'};
      for (final locale in AppLocale.values) {
        final policy = L10n(locale).t('legal_priv_cry_b').toLowerCase();
        expect(policy, contains(cry[locale]!),
            reason: '${locale.name} privacy policy does not mention the cry recording');
      }
    });
  });

  /// «Записи не сохраняются» has to be true of the PHONE as well.
  ///
  /// The server keeps its half of that promise and is held to it by
  /// packages/backend cryNotStored.test.ts, which watches every repository
  /// method for the bytes. The phone kept none of it: the clip was written to
  /// the temporary directory under one fixed name and left there after the
  /// upload, so the last recording of somebody's baby crying — made inside
  /// their home — stayed on the device until Android felt like reclaiming it,
  /// which can be never.
  ///
  /// Driven through the real [RecordCryRecorder] with real files, in the same
  /// order the screen calls it (stopAndRead, then upload). Only the microphone
  /// is faked; cry_insight_test.dart covers the screen's side of that order.
  group('the clip does not stay on the phone', () {
    /// A real directory on the real filesystem — the point of the test is what
    /// is on disk afterwards.
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cry_privacy_test');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    File clipFile() => File('${dir.path}/umay_cry.m4a');

    CryClassifierClient client({required bool succeeds, List<int>? seenBytes}) =>
        CryClassifierClient(
          baseUrl: Uri.parse('http://stub.local'),
          uploader: (url, bytes, name, headers) async {
            seenBytes?.addAll(bytes);
            if (!succeeds) throw const CryClassifierException('HTTP 502');
            return '{"reason":"hunger","confidence":0.8}';
          },
        );

    /// What the screen does on the auto-stop: read the clip, then upload it.
    Future<void> recordAndAnalyse({required bool uploadSucceeds, List<int>? seenBytes}) async {
      final recorder = RecordCryRecorder(mic: _FakeMic(), tempDir: () async => dir);
      expect(await recorder.start(), isTrue);
      expect(clipFile().existsSync(), isTrue, reason: 'the fake microphone wrote nothing');
      final bytes = await recorder.stopAndRead();
      expect(bytes, isNotNull);
      try {
        await client(succeeds: uploadSucceeds, seenBytes: seenBytes).analyze(bytes!);
      } on CryClassifierException {
        // the failure branch; the screen shows «не удалось»
      }
      await recorder.dispose();
    }

    test('after the analysis comes back, no recording is left', () async {
      final uploaded = <int>[];
      await recordAndAnalyse(uploadSucceeds: true, seenBytes: uploaded);
      // The clip still reached the classifier — a delete that ate the audio
      // would pass the line below and break the only feature on this screen.
      expect(uploaded, _FakeMic.clipBytes);
      expect(clipFile().existsSync(), isFalse,
          reason: 'the recording of her baby is still in the temp directory');
    });

    test('after the upload fails, no recording is left', () async {
      // A clip whose upload failed has no purpose at all — and this is the path
      // a happy-path delete leaves behind: bad signal, dropped connection, 502.
      await recordAndAnalyse(uploadSucceeds: false);
      expect(clipFile().existsSync(), isFalse,
          reason: 'a failed upload left the recording on the phone');
    });

    test('a recording she walked away from is not left either', () async {
      // Back-button two seconds in: the screen disposes the recorder and
      // stopAndRead is never called, so nothing else would ever remove it.
      final recorder = RecordCryRecorder(mic: _FakeMic(), tempDir: () async => dir);
      expect(await recorder.start(), isTrue);
      await recorder.dispose();
      expect(clipFile().existsSync(), isFalse,
          reason: 'an abandoned recording stayed in the temp directory');
    });
  });
}

/// Stands in for the `record` plugin: writes a clip where it is told to, as the
/// native recorder does, and nothing else.
class _FakeMic implements CryMic {
  static const clipBytes = [77, 65, 66, 67, 68];
  String? _path;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    _path = path;
    await File(path).writeAsBytes(clipBytes, flush: true);
  }

  @override
  Future<String?> stop() async => _path;

  @override
  Future<void> dispose() async {}
}
