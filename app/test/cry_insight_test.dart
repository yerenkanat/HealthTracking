/// Cry analysis: the client parses the service response, and the screen walks
/// record → analyse → result (and the mic-denied / error branches) with fakes
/// for the microphone and the network.
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/cry_classifier_client.dart';
import 'package:fcs_app/data/cry_recorder.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/cry_insight_screen.dart';

const _en = L10n(AppLocale.en);

const _okBody = '''
{"status":"success","primary_reason":"hungry","confidence":0.84,
 "probabilities":{"hungry":84,"tired":10,"belly_pain":4,"discomfort":2,"burping":0},
 "recommendation_ru":"Покормите малыша."}
''';

CryClassifierClient _client({String body = _okBody, bool throwing = false, void Function(Map<String, String>)? onHeaders}) =>
    CryClassifierClient(
      baseUrl: Uri.parse('http://test.local'),
      authToken: () async => 'tok-123',
      uploader: (url, bytes, name, headers) async {
        onHeaders?.call(headers);
        if (throwing) throw const CryClassifierException('boom');
        return body;
      },
    );

/// A recorder that never touches hardware.
class _FakeRecorder implements CryRecorder {
  final bool permission;
  final List<int>? bytes;
  _FakeRecorder({this.permission = true, this.bytes = const [1, 2, 3]});
  @override
  Future<bool> start() async => permission;
  @override
  Future<List<int>?> stopAndRead() async => bytes;
  @override
  Future<void> dispose() async {}
}

Widget _wrap(Widget child) => MaterialApp(home: L10nScope(l10n: _en, child: child));

void main() {
  group('CryClassifierClient', () {
    test('analyze parses the service JSON', () async {
      final a = await _client().analyze([1, 2, 3]);
      expect(a.primaryReason, 'hungry');
      expect(a.confidencePct, 84);
      expect(a.recommendationRu, 'Покормите малыша.');
    });

    test('empty recording throws before any upload', () async {
      expect(() => _client().analyze(const []), throwsA(isA<CryClassifierException>()));
    });

    test('a non-JSON body throws', () async {
      expect(() => _client(body: 'not json').analyze([1]), throwsA(isA<CryClassifierException>()));
    });

    test('attaches the bearer token and posts to the proxy path', () async {
      Uri? url;
      Map<String, String>? headers;
      final client = CryClassifierClient(
        baseUrl: Uri.parse('http://backend.local'),
        authToken: () async => 'tok-123',
        uploader: (u, bytes, name, h) async {
          url = u;
          headers = h;
          return _okBody;
        },
      );
      await client.analyze([1, 2, 3]);
      expect(url.toString(), 'http://backend.local/cry/analyze'); // Node proxy route
      expect(headers?['Authorization'], 'Bearer tok-123');
    });

    test('omits the auth header when signed out', () async {
      Map<String, String>? headers;
      final client = CryClassifierClient(
        baseUrl: Uri.parse('http://backend.local'),
        authToken: () async => null,
        uploader: (u, bytes, name, h) async {
          headers = h;
          return _okBody;
        },
      );
      await client.analyze([1]);
      expect(headers!.containsKey('Authorization'), isFalse);
    });
  });

  group('CryInsightScreen', () {
    testWidgets('record → analyse → shows the reason and recommendation', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(recorder: _FakeRecorder(), client: _client())));
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump(); // enter recording
      expect(find.text(_en.t('cry_recording')), findsWidgets);
      await tester.pump(const Duration(seconds: cryRecordSeconds)); // auto-stop fires
      await tester.pumpAndSettle();

      expect(find.text(_en.t('cry_result_title').toUpperCase()), findsOneWidget);
      expect(find.text(_en.t('cry_reason_hungry')), findsWidgets); // primary + bar
      expect(find.text('Покормите малыша.'), findsOneWidget);
      expect(find.text(_en.t('cry_confidence', {'n': 84})), findsOneWidget);
    });

    testWidgets('a denied microphone shows guidance, not a spinner', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(permission: false), client: _client())));
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('cry_mic_denied')), findsOneWidget);
    });

    testWidgets('a service error is explained', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(throwing: true))));
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: cryRecordSeconds));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('cry_error')), findsOneWidget);
    });

    testWidgets('an empty capture is treated as an error', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(bytes: const []), client: _client())));
      await tester.tap(find.text(_en.t('cry_record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: cryRecordSeconds));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('cry_error')), findsOneWidget);
    });
  });
}
