/// Frames 15 / 15a / 15b, the app half: the immunisation calendar the back
/// office publishes reaches the phone — WITHOUT the bundled one ever being at
/// risk.
///
/// Until this existed, `GET /vaccination/schedule` had no Dart caller at all.
/// The app read the compiled-in `kzSchedule` and a `const dueWindowMonths = 1`,
/// so moving the second pneumococcal dose was a backend release AND a store
/// rollout, and the panel's «затронет N детей» was a promise about nothing.
///
/// The two claims under test are the ones that matter to a parent:
///
///   * a month moved on the server moves the app's own verdict between «пора»
///     and «стоит наверстать» — not just the label on a row, the section the
///     row lands in;
///   * a phone with no signal still opens the whole calendar.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/data/vaccination_schedule_repository.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/vaccination.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/vaccination_screen.dart';

const ru = L10n(AppLocale.ru);
final today = DateTime(2026, 7, 22);

ChildProfile childAged(int months) => ChildProfile(
      id: 'c1',
      name: 'Сұлтан',
      dateOfBirth: DateTime(today.year, today.month - months, today.day),
    );

/// One `/vaccination/schedule` payload, in the shape vaccination/overrides.ts
/// serves: the whole calendar, merged, plus the catch-up window.
///
/// `kk`, `ruNote` and `kkNote` are ABSENT unless somebody wrote them — that is
/// the server's rule, and the app's l10n fallback depends on it.
String payload({
  int version = 7,
  int dueWindowMonths = 1,
  Map<String, int> movedTo = const {},
  List<Map<String, Object?>> extra = const [],
}) {
  final vaccines = [
    for (final v in kzSchedule)
      {
        'key': vaccineKey(v),
        'id': v.id,
        'atMonth': movedTo[vaccineKey(v)] ?? v.atMonth,
        if (v.dose != null) 'dose': v.dose,
        'ru': _contractRu[v.id]!,
      },
    ...extra,
  ]..sort((a, b) => (a['atMonth'] as int).compareTo(b['atMonth'] as int));
  return jsonEncode({
    'version': version,
    'dueWindowMonths': dueWindowMonths,
    'vaccines': vaccines,
  });
}

const _contractRu = {
  'hepb': 'Гепатит B',
  'bcg': 'БЦЖ',
  'pentavalent': 'Пятивалентная (АКДС + гепатит B + Hib)',
  'opv': 'Полиомиелит',
  'pcv': 'Пневмококковая',
  'mmr': 'Корь, паротит, краснуха (ККП)',
  'dtp': 'АКДС (ревакцинация)',
  'hib': 'Гемофильная инфекция (ревакцинация)',
  'adt': 'АДС-М',
};

class _Transport implements HttpTransport {
  _Transport(this.reply, {this.status = 200});

  /// What GET /vaccination/schedule answers, or null to make the call fail.
  final String? reply;
  final int status;
  final List<String> calls = [];

  @override
  Future<HttpResponse> get(String path) async {
    calls.add(path);
    if (reply == null) throw Exception('no network');
    return HttpResponse(status, reply!);
  }

  @override
  Future<HttpResponse> post(String path, Object body) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) => get(path);
}

class _MemoryCache implements VaccinationScheduleCache {
  String? stored;
  @override
  Future<String?> read() async => stored;
  @override
  Future<void> write(String json) async => stored = json;
}

Future<void> pump(WidgetTester tester, ChildProfile child) async {
  // Tall: the full schedule is a long list, and a short surface lets a lazy
  // ListView skip the sections these tests are about.
  tester.view.physicalSize = const Size(880, 6400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: ru,
      child: VaccinationScreen(child: child, today: today),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The vaccines the screen would put under «стоит наверстать», by key.
Set<String> catchUpKeys(int ageMonths) => {
      for (final v in vaccinesToCatchUp(
          ageMonths, const {}, servedVaccines(), servedDueWindowMonths()))
        vaccineKey(v)
    };

Set<String> dueKeys(int ageMonths) => {
      for (final v
          in vaccinesDue(ageMonths, servedVaccines(), servedDueWindowMonths()))
        vaccineKey(v)
    };

void main() {
  // Module state, so every test starts from a phone that has never had signal.
  setUp(debugResetVaccinationSchedule);
  tearDown(debugResetVaccinationSchedule);

  group('a phone that has never reached the server', () {
    test('reads the bundled calendar and the shipped window', () {
      expect(servedVaccines(), same(kzSchedule));
      expect(servedDueWindowMonths(), dueWindowMonths);
      expect(vaccinationScheduleIsFromServer(), isFalse);
    });

    test('a failed refresh reports failure and changes nothing', () async {
      final api = ApiClient(_Transport(null));
      expect(await refreshVaccinationScheduleFromApi(api: api), isNull,
          reason: 'a failure must be reported as a failure');
      expect(servedVaccines(), same(kzSchedule));
      expect(servedDueWindowMonths(), dueWindowMonths);
      expect(vaccinationScheduleIsFromServer(), isFalse);
    });

    testWidgets('still opens the whole calendar, offline', (tester) async {
      final api = ApiClient(_Transport(null));
      await refreshVaccinationScheduleFromApi(api: api);
      await pump(tester, childAged(2));

      // Every scheduled age is on screen, not just the ones that are due.
      expect(find.text(ru.t('vac_at_birth')), findsOneWidget);
      expect(find.text(ru.t('vac_at_month', {'n': 12})), findsOneWidget);
      expect(find.textContaining(ru.t('vac_pcv')), findsWidgets);
      // ...and it says it is the build's own table rather than claiming to be
      // freshly published.
      expect(find.text(ru.t('vac_revision', {'d': scheduleRevision})), findsOneWidget);
      expect(find.textContaining('vac_'), findsNothing);
    });
  });

  group('a month moved in the back office moves the verdict', () {
    test('pcv/2 pushed from 4 to 9 months leaves the catch-up list', () async {
      // A six-month-old, nothing recorded. Under the shipped calendar the
      // second pneumococcal dose is past its window (4 + 1 < 6) and sits in
      // «стоит наверстать».
      expect(catchUpKeys(6), contains('pcv/2'));

      final api = ApiClient(_Transport(payload(movedTo: {'pcv/2': 9})));
      final n = await refreshVaccinationScheduleFromApi(api: api);
      expect(n, kzSchedule.length);

      // ...and after the edit it is simply not due yet.
      expect(catchUpKeys(6), isNot(contains('pcv/2')));
      expect(dueKeys(6), isNot(contains('pcv/2')));
      expect(dueKeys(9), contains('pcv/2'), reason: '«пора» at the new age');
      // The rest of the calendar did not move with it.
      expect(catchUpKeys(6), contains('pcv/1'));
    });

    testWidgets('the screen puts the row in the other section', (tester) async {
      await pump(tester, childAged(6));
      expect(find.text(ru.t('vac_catchup')), findsOneWidget);
      final before = tester.widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').contains(ru.t('vac_pcv')))
          .length;

      final api = ApiClient(_Transport(payload(movedTo: {
        'pcv/1': 9, 'pcv/2': 11,
      })));
      await refreshVaccinationScheduleFromApi(api: api);
      await pump(tester, childAged(6));

      // Both pneumococcal doses are now ahead of this child, so neither can be
      // in the catch-up list; the row count in the whole list drops because the
      // catch-up section no longer repeats them.
      final after = tester.widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').contains(ru.t('vac_pcv')))
          .length;
      expect(after, lessThan(before));
      // And the age heading the server chose is the one drawn.
      expect(find.text(ru.t('vac_at_month', {'n': 11})), findsOneWidget);
    });

    test('a moved dose keeps its key, so a mother’s tick still counts', () async {
      final api = ApiClient(_Transport(payload(movedTo: {'pcv/2': 9})));
      await refreshVaccinationScheduleFromApi(api: api);
      final moved = servedVaccines().firstWhere((v) => vaccineKey(v) == 'pcv/2');
      expect(moved.atMonth, 9);
      expect(moved.dose, 2);
      // `child_vaccines.vaccine_key` is filed under this string. Re-keying it
      // here would silently orphan every tick already recorded.
      expect(vaccineKey(moved), 'pcv/2');
      expect(vaccinesToCatchUp(20, {'pcv/2'}, servedVaccines(), servedDueWindowMonths())
          .map(vaccineKey), isNot(contains('pcv/2')));
    });
  });

  group('the catch-up window is the back office’s, not a constant', () {
    test('widening it turns «наверстать» back into «пора»', () async {
      // Six months old, a vaccine scheduled at four. Window 1: passed.
      expect(catchUpKeys(6), contains('pcv/2'));

      final api = ApiClient(_Transport(payload(dueWindowMonths: 3)));
      await refreshVaccinationScheduleFromApi(api: api);
      expect(servedDueWindowMonths(), 3);

      // 6 <= 4 + 3 — her own screen now says «пора», which is the same boundary
      // the panel's coverage denominator is drawn on.
      expect(dueKeys(6), contains('pcv/2'));
      expect(catchUpKeys(6), isNot(contains('pcv/2')));
    });

    testWidgets('and the section on screen follows it', (tester) async {
      final api = ApiClient(_Transport(payload(dueWindowMonths: 6)));
      await refreshVaccinationScheduleFromApi(api: api);
      await pump(tester, childAged(6));
      // Nothing is past a six-month window for a six-month-old.
      expect(find.text(ru.t('vac_catchup')), findsNothing);
      expect(find.text(ru.t('vac_due')), findsOneWidget);
    });

    test('a window outside 1..12 falls back to the shipped one', () async {
      // A bad window is one wrong boundary; rejecting the payload over it would
      // be sixteen stale rows.
      final api = ApiClient(_Transport(payload(dueWindowMonths: 99, movedTo: {'pcv/2': 9})));
      await refreshVaccinationScheduleFromApi(api: api);
      expect(servedDueWindowMonths(), dueWindowMonths);
      expect(servedVaccines().firstWhere((v) => vaccineKey(v) == 'pcv/2').atMonth, 9);
    });
  });

  group('the cache is what an offline launch reads', () {
    test('a refresh stores the exact bytes it received', () async {
      final cache = _MemoryCache();
      final raw = payload(movedTo: {'pcv/2': 9});
      await refreshVaccinationScheduleFromApi(
          api: ApiClient(_Transport(raw)), cache: cache);
      // Not a re-encode: a field this build does not understand has to survive
      // to the next launch.
      expect(cache.stored, raw);
    });

    test('priming from it applies the newest calendar this phone ever had', () async {
      final cache = _MemoryCache()..stored = payload(movedTo: {'pcv/2': 9}, dueWindowMonths: 2);
      await primeVaccinationScheduleFromCache(cache);
      expect(servedVaccines().firstWhere((v) => vaccineKey(v) == 'pcv/2').atMonth, 9);
      expect(servedDueWindowMonths(), 2);
      expect(vaccinationScheduleIsFromServer(), isTrue);
    });

    test('no cache is an ordinary first launch, not a degradation', () async {
      await primeVaccinationScheduleFromCache(_MemoryCache());
      expect(servedVaccines(), same(kzSchedule));
      expect(vaccinationScheduleIsFromServer(), isFalse);
    });

    test('a corrupt cache leaves the bundled calendar alone', () async {
      await primeVaccinationScheduleFromCache(_MemoryCache()..stored = 'not json at all');
      expect(servedVaccines(), same(kzSchedule));
    });

    test('a cached calendar survives a failed refresh', () async {
      final cache = _MemoryCache()..stored = payload(movedTo: {'pcv/2': 9});
      await primeVaccinationScheduleFromCache(cache);
      expect(await refreshVaccinationScheduleFromApi(
          api: ApiClient(_Transport(null)), cache: cache), isNull);
      expect(servedVaccines().firstWhere((v) => vaccineKey(v) == 'pcv/2').atMonth, 9);
    });
  });

  group('what the app refuses to adopt', () {
    test('an empty schedule is never an answer', () async {
      final api = ApiClient(_Transport(jsonEncode({'version': 9, 'vaccines': []})));
      expect(await refreshVaccinationScheduleFromApi(api: api), isNull);
      expect(servedVaccines(), same(kzSchedule));
    });

    test('a row with no id or an impossible age is dropped, the rest kept', () async {
      final api = ApiClient(_Transport(jsonEncode({
        'version': 9,
        'dueWindowMonths': 1,
        'vaccines': [
          {'id': '', 'atMonth': 2, 'ru': 'без кода'},
          {'id': 'ghost', 'atMonth': -3, 'ru': 'до рождения'},
          {'id': 'bcg', 'atMonth': 0, 'ru': 'БЦЖ'},
        ],
      })));
      expect(await refreshVaccinationScheduleFromApi(api: api), 1);
      expect(servedVaccines().map((v) => v.id), ['bcg']);
    });

    test('a non-200 keeps what we have', () async {
      final api = ApiClient(_Transport(payload(movedTo: {'pcv/2': 9}), status: 503));
      expect(await refreshVaccinationScheduleFromApi(api: api), isNull);
      expect(servedVaccines(), same(kzSchedule));
    });
  });

  group('what the words on a row come from', () {
    testWidgets('an untouched vaccine keeps the app’s own translations',
        (tester) async {
      // The server sends a Russian label and no Kazakh: the contract has none,
      // and `vac_bcg` in this build's l10n is a better Kazakh name than
      // anything the merge could invent.
      await refreshVaccinationScheduleFromApi(api: ApiClient(_Transport(payload())));
      final v = servedVaccines().firstWhere((x) => x.id == 'bcg');
      expect(v.kk, isNull);
      expect(vaccineName(const L10n(AppLocale.kk), v), ru.t('vac_bcg'));
      expect(vaccineName(const L10n(AppLocale.en), v), 'BCG');

      await pump(tester, childAged(2));
      expect(find.textContaining('vac_'), findsNothing);
    });

    test('an edited name wins over l10n', () async {
      await refreshVaccinationScheduleFromApi(api: ApiClient(_Transport(jsonEncode({
        'version': 9,
        'dueWindowMonths': 1,
        'vaccines': [
          {'key': 'pcv/1', 'id': 'pcv', 'atMonth': 2, 'dose': 1,
            'ru': 'Пневмококковая (ПКВ-13)', 'kk': 'Пневмококк (ПКВ-13)',
            'ruNote': 'Против пневмонии и отита', 'kkNote': 'Пневмония мен отитке қарсы'},
        ],
      }))));
      final v = servedVaccines().single;
      expect(vaccineName(ru, v), 'Пневмококковая (ПКВ-13)');
      expect(vaccineName(const L10n(AppLocale.kk), v), 'Пневмококк (ПКВ-13)');
      expect(vaccineNote(ru, v), 'Против пневмонии и отита');
    });

    testWidgets('a vaccine ADDED in the back office renders its own words',
        (tester) async {
      // Frame 15a. It has no l10n key at all, so the server's text is the only
      // text it will ever have — and a raw `vac_rota` on a parent's screen is
      // the failure this checks for.
      await refreshVaccinationScheduleFromApi(api: ApiClient(_Transport(payload(extra: [
        {'key': 'rota/1', 'id': 'rota', 'atMonth': 2, 'dose': 1,
          'ru': 'Ротавирусная', 'kk': 'Ротавирус',
          'ruNote': 'Против тяжёлой кишечной инфекции',
          'kkNote': 'Ауыр ішек инфекциясына қарсы', 'added': true},
      ]))));
      final v = servedVaccines().firstWhere((x) => x.id == 'rota');
      expect(v.added, isTrue);

      await pump(tester, childAged(2));
      expect(find.textContaining('Ротавирусная'), findsWidgets);
      expect(find.textContaining('vac_rota'), findsNothing);
    });

    testWidgets('a served calendar says it came from the service, not the build',
        (tester) async {
      await refreshVaccinationScheduleFromApi(api: ApiClient(_Transport(payload())));
      await pump(tester, childAged(6));
      expect(find.text(ru.t('vac_source_server')), findsOneWidget);
      expect(find.text(ru.t('vac_revision', {'d': scheduleRevision})), findsNothing);
    });
  });
}
