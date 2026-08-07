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

    test('the privacy policy lists the recording too', () {
      // It named chat messages and band readings and omitted the one piece of
      // audio — the most sensitive thing the app sends anywhere.
      const cry = {AppLocale.ru: 'плач', AppLocale.kk: 'жылау', AppLocale.en: 'cry'};
      for (final locale in AppLocale.values) {
        final policy = L10n(locale).t('legal_priv_cloud_b').toLowerCase();
        expect(policy, contains(cry[locale]!),
            reason: '${locale.name} privacy policy does not mention the cry recording');
      }
    });
  });
}
