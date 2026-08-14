/// Кадр 17c, the app half: the detector says «не уверены» when it is not sure,
/// and the mother can tell it when it was wrong.
///
/// Two claims, and neither one is provable by reading the screen's source:
///
///   1. below the served threshold the screen NAMES NO REASON. «Голод» at 31 %
///      reads to a mother exactly like «Голод» at 91 %, and she feeds a baby
///      who is in pain. The bars stay — a flat spread IS the answer — and the
///      recommendation goes, because «Покормите малыша» names the reason in
///      prose that the headline has just refused to name.
///   2. the threshold arrives from the server. It was a Dart constant, so
///      raising it meant a store rollout for every phone.
///
/// Plus «Это было верно?», the only ground truth this product will ever have
/// about why a baby cried: nothing here reads a clinic, and the recording is
/// never stored, so a rating that silently fails can never be recovered — and
/// the screen must not thank her for one.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/data/cry_classifier_client.dart';
import 'package:fcs_app/data/cry_recorder.dart';
import 'package:fcs_app/data/cry_settings_repository.dart';
import 'package:fcs_app/domain/cry_analysis.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/cry_insight_screen.dart';

const _en = L10n(AppLocale.en);

/// A confident answer (84 %) and a hesitant one (31 %) — the two sides of the
/// threshold, from the same service shape.
String _body({int pct = 84}) => jsonEncode({
      'status': 'success',
      'primary_reason': 'hungry',
      'confidence': pct / 100,
      'probabilities': {'hungry': pct, 'tired': 100 - pct},
      'recommendation_ru': 'Покормите малыша.',
    });

CryClassifierClient _client({int pct = 84}) => CryClassifierClient(
      baseUrl: Uri.parse('http://test.local'),
      uploader: (url, bytes, name, headers) async => _body(pct: pct),
    );

class _FakeRecorder implements CryRecorder {
  @override
  Future<bool> start() async => true;
  @override
  Future<List<int>?> stopAndRead() async => const [1, 2, 3];
  @override
  Future<void> dispose() async {}
}

Widget _wrap(Widget child) => MaterialApp(home: L10nScope(l10n: _en, child: child));

/// Tap something that may be below the fold.
///
/// The verdict card sits under the result card, which sits under a 116px mic
/// button: on the 800×600 test viewport it is off-screen, and `tap()` on an
/// off-screen widget warns and hits nothing — which reads as "the button does
/// not work" rather than "the test never pressed it".
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Record → analyse → result, in one step.
///
/// The mic button is labelled «Записать плач» the first time and «Записать ещё
/// раз» afterwards, so a second run has to press the button by what it says
/// now — and it may have been scrolled off by the result below it.
Future<void> _analyse(WidgetTester tester, {L10n l = _en}) async {
  final first = find.text(l.t('cry_record'));
  final mic = first.evaluate().isNotEmpty ? first : find.text(l.t('cry_again'));
  await tester.ensureVisible(mic);
  await tester.pumpAndSettle();
  await tester.tap(mic);
  await tester.pump();
  await tester.pump(const Duration(seconds: cryRecordSeconds));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// The threshold, over the wire.
// ---------------------------------------------------------------------------

class _Transport implements HttpTransport {
  _Transport(this.reply);
  final String? reply;
  final List<String> calls = [];
  final List<(String, Object)> posts = [];
  int postStatus = 200;

  @override
  Future<HttpResponse> get(String path) async {
    calls.add(path);
    if (reply == null) throw Exception('no network');
    return HttpResponse(200, reply!);
  }

  @override
  Future<HttpResponse> post(String path, Object body) async {
    posts.add((path, body));
    return HttpResponse(postStatus, '{}');
  }

  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) => get(path);
}

void main() {
  // Each test starts from the shipped default, whatever an earlier one adopted:
  // the threshold is process-wide state, exactly as it is in the running app.
  setUp(() => debugSetCryMinConfidence(kCryMinConfidenceDefault));

  group('below the threshold nothing is named', () {
    testWidgets('a 31 % answer says «не уверены» and names no reason', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(pct: 31))));
      await _analyse(tester);

      expect(find.text(_en.t('cry_unsure_headline')), findsOneWidget);
      expect(find.text(_en.t('cry_unsure_body')), findsOneWidget);
      // The bars are still there — one of them is labelled «Hunger» — but the
      // HEADLINE is not, and neither is the recommendation.
      expect(find.text(_en.t('cry_reason_hungry')), findsOneWidget); // the bar only
      expect(find.text('Покормите малыша.'), findsNothing);
      // The number itself is still shown: hiding it would leave her unable to
      // tell a near-miss from a shrug.
      expect(find.text(_en.t('cry_confidence', {'n': 31})), findsOneWidget);
    });

    testWidgets('an 84 % answer names it, with the advice', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client())));
      await _analyse(tester);
      expect(find.text(_en.t('cry_result_title').toUpperCase()), findsOneWidget);
      expect(find.text(_en.t('cry_unsure_headline')), findsNothing);
      expect(find.text('Покормите малыша.'), findsOneWidget);
    });

    testWidgets('the threshold decides, not the number 45', (tester) async {
      // The same 84 % answer, under a threshold the back office raised to 90.
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(), minConfidence: 0.9)));
      await _analyse(tester);
      expect(find.text(_en.t('cry_unsure_headline')), findsOneWidget);
      expect(find.text('Покормите малыша.'), findsNothing);
    });

    testWidgets('a past unsure result is not named in the history either', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(),
        client: _client(),
        history: [
          CryResult(reason: 'tired', confidence: 0.2, at: DateTime(2026, 7, 20)),
          CryResult(reason: 'hungry', confidence: 0.9, at: DateTime(2026, 7, 19)),
        ],
      )));
      await tester.pumpAndSettle();
      // The app must not name in the list what it refused to name on the card.
      expect(find.text(_en.t('cry_reason_tired')), findsNothing);
      expect(find.text(_en.t('cry_unsure_headline')), findsOneWidget);
      expect(find.text(_en.t('cry_reason_hungry')), findsOneWidget);
    });
  });

  group('the threshold comes from the server', () {
    test('the shipped default applies before anything is fetched', () {
      expect(cryMinConfidence(), kCryMinConfidenceDefault);
    });

    test('a served threshold is adopted and cached', () async {
      final t = _Transport(jsonEncode({
        'minConfidence': 0.7, 'defaultMinConfidence': 0.45, 'source': 'override',
      }));
      final v = await refreshCryThresholdFromApi(api: ApiClient(t));
      expect(v, 0.7);
      expect(cryMinConfidence(), 0.7);
      expect(t.calls.single, '/protocols/cry');
    });

    test('an unreachable server leaves the threshold alone', () async {
      final v = await refreshCryThresholdFromApi(api: ApiClient(_Transport(null)));
      expect(v, isNull);
      // Not zero. Zero would switch the rule off and let a 12 % guess be
      // announced as the reason.
      expect(cryMinConfidence(), kCryMinConfidenceDefault);
    });

    test('a threshold no answer could reach is refused', () async {
      final t = _Transport(jsonEncode({'minConfidence': 1.0}));
      expect(await refreshCryThresholdFromApi(api: ApiClient(t)), isNull);
      expect(cryMinConfidence(), kCryMinConfidenceDefault);
    });

    test('nonsense in the payload does not become a threshold', () async {
      for (final body in ['{}', '[]', 'not json', jsonEncode({'minConfidence': 'high'})]) {
        expect(await refreshCryThresholdFromApi(api: ApiClient(_Transport(body))), isNull);
        expect(cryMinConfidence(), kCryMinConfidenceDefault);
      }
    });
  });

  group('«Это было верно?»', () {
    testWidgets('is not asked when no reason was named', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(pct: 31),
        onVerdict: (_, __) => true)));
      await _analyse(tester);
      // A question about an answer that was never given.
      expect(find.text(_en.t('cry_verdict_q')), findsNothing);
    });

    testWidgets('«да» is reported and confirmed', (tester) async {
      final answers = <(String, String?)>[];
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(),
        onVerdict: (v, a) { answers.add((v, a)); return true; })));
      await _analyse(tester);
      await _tap(tester, find.text(_en.t('cry_verdict_yes')));
      expect(answers, [('correct', null)]);
      expect(find.text(_en.t('cry_verdict_thanks')), findsOneWidget);
    });

    testWidgets('«нет» asks what it actually was, and sends that', (tester) async {
      final answers = <(String, String?)>[];
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(),
        onVerdict: (v, a) { answers.add((v, a)); return true; })));
      await _analyse(tester);
      await _tap(tester, find.text(_en.t('cry_verdict_no')));
      expect(find.text(_en.t('cry_verdict_which')), findsOneWidget);
      // Nothing is recorded until she picks — «нет» alone is half an answer.
      expect(answers, isEmpty);

      await _tap(tester, find.text(_en.t('cry_reason_belly_pain')).last);
      expect(answers, [('wrong', 'belly_pain')]);
    });

    testWidgets('«не знаю» is a real answer, not a forced guess', (tester) async {
      final answers = <(String, String?)>[];
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(),
        onVerdict: (v, a) { answers.add((v, a)); return true; })));
      await _analyse(tester);
      await _tap(tester, find.text(_en.t('cry_verdict_no')));
      await _tap(tester, find.text(_en.t('cry_verdict_dont_know')));
      expect(answers, [('wrong', null)]);
    });

    testWidgets('a rating that could not be recorded is not thanked for', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(),
        onVerdict: (_, __) => false)));
      await _analyse(tester);
      await _tap(tester, find.text(_en.t('cry_verdict_yes')));
      expect(find.text(_en.t('cry_verdict_thanks')), findsNothing);
      expect(find.text(_en.t('cry_verdict_failed')), findsOneWidget);
      // …and the question is still open, so she can try again.
      expect(find.text(_en.t('cry_verdict_yes')), findsOneWidget);
    });

    testWidgets('a new recording clears the previous answer', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(), client: _client(),
        onVerdict: (_, __) => true)));
      await _analyse(tester);
      await _tap(tester, find.text(_en.t('cry_verdict_yes')));
      expect(find.text(_en.t('cry_verdict_thanks')), findsOneWidget);

      await _analyse(tester); // record again
      // A tick carried over would show an answer under an analysis nobody rated.
      expect(find.text(_en.t('cry_verdict_thanks')), findsNothing);
      expect(find.text(_en.t('cry_verdict_q')), findsOneWidget);
    });

    testWidgets('an answer already given is shown in the history', (tester) async {
      await tester.pumpWidget(_wrap(CryInsightScreen(
        recorder: _FakeRecorder(),
        client: _client(),
        history: [
          CryResult(reason: 'hungry', confidence: 0.9, at: DateTime(2026, 7, 20),
              verdict: CryVerdict.wrong, actualReason: 'belly_pain'),
        ],
      )));
      await tester.pumpAndSettle();
      expect(
          find.text(_en.t('cry_verdict_was_wrong_actual',
              {'reason': _en.t('cry_reason_belly_pain')})),
          findsOneWidget);
    });
  });

  group('the controller keeps and pushes the verdict', () {
    AppController make() =>
        AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    CryAnalysis analysis(String reason, double conf) => CryAnalysis(
        primaryReason: reason, confidence: conf,
        probabilities: {reason: (conf * 100).round()}, recommendationRu: '');

    test('rateLatestCry marks the newest result and pushes it', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <CryResult>[];
      c.attachCryVerdictSync(push: (r) async => pushed.add(r));
      c.recordCry(analysis('tired', 0.5));
      c.recordCry(analysis('hungry', 0.9)); // the newest — the one on screen

      expect(c.rateLatestCry(CryVerdict.wrong, actualReason: 'belly_pain'), isTrue);
      expect(c.cryHistory.first.verdict, CryVerdict.wrong);
      expect(c.cryHistory.first.actualReason, 'belly_pain');
      // The older one is untouched: the question was about the analysis shown.
      expect(c.cryHistory[1].verdict, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(pushed.single.reason, 'hungry');
    });

    test('«верно» carries no actual reason', () {
      final c = make();
      addTearDown(c.dispose);
      c.recordCry(analysis('hungry', 0.9));
      c.rateLatestCry(CryVerdict.correct, actualReason: 'tired');
      expect(c.cryHistory.first.actualReason, isNull);
    });

    test('with nothing recorded there is nothing to rate, and it says so', () {
      final c = make();
      addTearDown(c.dispose);
      expect(c.rateLatestCry(CryVerdict.correct), isFalse);
    });

    test('the verdict survives a JSON round trip', () {
      final r = CryResult(
          reason: 'hungry', confidence: 0.9, at: DateTime.utc(2026, 7, 23),
          verdict: CryVerdict.wrong, actualReason: 'tired');
      final back = CryResult.fromJson(r.toJson());
      expect(back.verdict, CryVerdict.wrong);
      expect(back.actualReason, 'tired');
    });

    test('a history written before verdicts existed reads as unrated', () {
      final back = CryResult.fromJson(
          {'reason': 'hungry', 'confidence': 0.9, 'at': '2026-07-23T00:00:00.000Z'});
      expect(back.verdict, isNull);
      expect(back.actualReason, isNull);
    });

    test('a verdict word this build does not know reads as unrated, not as a tick', () {
      final back = CryResult.fromJson({
        'reason': 'hungry', 'confidence': 0.9, 'at': '2026-07-23T00:00:00.000Z',
        'verdict': 'partly',
      });
      expect(back.verdict, isNull);
    });

    test('the server spelling of actual_reason is understood', () {
      // GET /cry/results answers `actualReason`; a hand-written payload or an
      // older server may use the column name. Both are the same fact.
      final back = CryResult.fromJson({
        'reason': 'hungry', 'confidence': 0.9, 'at': '2026-07-23T00:00:00.000Z',
        'verdict': 'wrong', 'actual_reason': 'tired',
      });
      expect(back.actualReason, 'tired');
    });
  });

  group('the verdict reaches the API', () {
    test('postCryVerdict puts the instant in the path and the answer in the body', () async {
      final t = _Transport('{}');
      await ApiClient(t).postCryVerdict(
          at: '2026-08-10T21:14:00.000Z', verdict: 'wrong', actualReason: 'tired');
      final (path, body) = t.posts.single;
      expect(path, contains('/cry/results/'));
      expect(path, contains('verdict'));
      expect(body, {'verdict': 'wrong', 'actualReason': 'tired'});
    });

    test('a refusal is raised, not swallowed', () async {
      final t = _Transport('{}')..postStatus = 404;
      expect(
          () => ApiClient(t)
              .postCryVerdict(at: '2026-08-10T21:14:00.000Z', verdict: 'correct'),
          throwsA(isA<ApiException>()));
    });
  });
}
