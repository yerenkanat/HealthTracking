/// Frame 14a/14b, the app half: a week edited in the back office reaches the
/// phone — WITHOUT the bundled calendar ever being at risk.
///
/// The week screen used to read the asset and nothing else, so every edit in
/// the panel stopped at the panel. These drive the layering the other way too:
/// the server is allowed to change a week, and is not allowed to take one away.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/data/pregnancy_weeks_repository.dart';
import 'package:fcs_app/domain/pregnancy_week_content.dart';

/// The calendar this build ships with — three weeks is enough to show that the
/// two the server does not mention survive.
const _bundled = [
  PregnancyWeekContent(
    week: 21, lengthCm: '26,7', hcg: '—',
    ru: PregnancyWeekText(baby: 'BUNDLED 21 baby', you: 'BUNDLED 21 you', recommend: 'BUNDLED 21 rec'),
    kk: PregnancyWeekText(baby: 'КІТАПХАНА 21', you: 'сіз 21', recommend: 'ұсыныс 21'),
  ),
  PregnancyWeekContent(
    week: 22, lengthCm: '27,8', hcg: '4720',
    ru: PregnancyWeekText(baby: 'BUNDLED 22 baby', you: 'BUNDLED 22 you', recommend: 'BUNDLED 22 rec'),
    kk: PregnancyWeekText(baby: 'КІТАПХАНА 22', you: 'сіз 22', recommend: 'ұсыныс 22'),
  ),
  PregnancyWeekContent(
    week: 23, lengthCm: '28,9', hcg: '—',
    ru: PregnancyWeekText(baby: 'BUNDLED 23 baby', you: 'BUNDLED 23 you', recommend: 'BUNDLED 23 rec'),
    kk: PregnancyWeekText(baby: 'КІТАПХАНА 23', you: 'сіз 23', recommend: 'ұсыныс 23'),
  ),
];

String _payload(List<Map<String, Object?>> weeks, {int version = 2}) =>
    jsonEncode({'version': version, 'weeks': weeks});

Map<String, Object?> _week(int week, String babyRu,
        {String kkBaby = 'ЖАҢА', String lengthCm = '27,8'}) =>
    {
      'week': week,
      'lengthCm': lengthCm,
      'hcg': '9999',
      'ru': {'baby': babyRu, 'you': 'SERVER you', 'recommend': 'SERVER rec'},
      'kk': {'baby': kkBaby, 'you': 'сервер', 'recommend': 'ұсыныс'},
    };

class _Transport implements HttpTransport {
  _Transport(this.reply);

  /// What GET /pregnancy/weeks answers, or null to make the call fail.
  final String? reply;
  final List<String> calls = [];

  @override
  Future<HttpResponse> get(String path) async {
    calls.add(path);
    if (reply == null) throw Exception('no network');
    return HttpResponse(200, reply!);
  }

  @override
  Future<HttpResponse> post(String path, Object body) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) => get(path);
}

class _MemoryCache implements PregnancyWeeksCache {
  String? stored;
  @override
  Future<String?> read() async => stored;
  @override
  Future<void> write(String json) async => stored = json;
}

void main() {
  setUp(() => debugSetPregnancyWeeks(_bundled));
  tearDown(() => debugSetPregnancyWeeks(const []));

  test('with no refresh the bundled calendar is what the screen reads', () async {
    final weeks = await loadPregnancyWeeks();
    expect(weeks.map((w) => w.week), [21, 22, 23]);
    expect(weekContentFor(weeks, 22)!.ru.baby, 'BUNDLED 22 baby');
  });

  test('a published edit to week 22 replaces that week and only that week', () async {
    final api = ApiClient(_Transport(_payload([_week(22, 'SERVER 22 baby')])));
    final n = await refreshPregnancyWeeksFromApi(api: api);
    expect(n, 1);

    final weeks = await loadPregnancyWeeks();
    expect(weekContentFor(weeks, 22)!.ru.baby, 'SERVER 22 baby');
    expect(weekContentFor(weeks, 22)!.kk.baby, 'ЖАҢА');
    // The two the server did not mention are untouched — this is the whole
    // difference between layering and replacing.
    expect(weekContentFor(weeks, 21)!.ru.baby, 'BUNDLED 21 baby');
    expect(weekContentFor(weeks, 23)!.ru.baby, 'BUNDLED 23 baby');
    expect(weeks, hasLength(3));
  });

  test('en still falls back to ru on a server-published week', () async {
    // The calendar carries ru + kk only, and a clinical blank is worse than a
    // Russian sentence a bilingual user can read. The merged path must keep it.
    final api = ApiClient(_Transport(_payload([_week(22, 'SERVER 22 baby')])));
    await refreshPregnancyWeeksFromApi(api: api);
    final w = weekContentFor(await loadPregnancyWeeks(), 22)!;
    expect(w.textFor('en').baby, 'SERVER 22 baby');
    expect(w.textFor('kk').baby, 'ЖАҢА');
  });

  test('the server going offline leaves the bundled week on screen', () async {
    final api = ApiClient(_Transport(null));
    final n = await refreshPregnancyWeeksFromApi(api: api);
    expect(n, isNull, reason: 'a failure must be reported as a failure');
    final weeks = await loadPregnancyWeeks();
    expect(weeks, hasLength(3));
    expect(weekContentFor(weeks, 22)!.ru.baby, 'BUNDLED 22 baby');
  });

  test('a server response that lost a week does not lose it here', () async {
    // Defensive: the server merges the contract into what it serves, so this
    // should not happen — and if it ever does, the bundled week is still a
    // better answer than a blank card about somebody's pregnancy.
    final api = ApiClient(_Transport(_payload([_week(21, 'SERVER 21 baby')])));
    await refreshPregnancyWeeksFromApi(api: api);
    final weeks = await loadPregnancyWeeks();
    expect(weeks.map((w) => w.week), [21, 22, 23]);
    expect(weekContentFor(weeks, 22)!.ru.baby, 'BUNDLED 22 baby');
  });

  test('an empty week from the server does not blank a real bundled one', () async {
    final api = ApiClient(_Transport(_payload([
      {'week': 22, 'lengthCm': '', 'hcg': '', 'ru': {'baby': '', 'you': '', 'recommend': ''}, 'kk': {'baby': '', 'you': '', 'recommend': ''}},
    ])));
    await refreshPregnancyWeeksFromApi(api: api);
    expect(weekContentFor(await loadPregnancyWeeks(), 22)!.ru.baby, 'BUNDLED 22 baby');
  });

  test('a malformed payload is ignored rather than emptying the calendar', () async {
    final api = ApiClient(_Transport('<html>502 Bad Gateway</html>'));
    expect(await refreshPregnancyWeeksFromApi(api: api), isNull);
    expect((await loadPregnancyWeeks()), hasLength(3));
  });

  test('caches the exact bytes and replays them on the next cold launch', () async {
    final cache = _MemoryCache();
    final api = ApiClient(_Transport(_payload([_week(22, 'SERVER 22 baby')])));
    await refreshPregnancyWeeksFromApi(api: api, cache: cache);
    expect(cache.stored, contains('SERVER 22 baby'));

    // A new launch: the asset loads, then the cache is primed BEFORE any
    // network call. Offline, she still reads the newest text this phone ever
    // received rather than falling back to the build's asset.
    debugSetPregnancyWeeks(_bundled);
    expect(weekContentFor(await loadPregnancyWeeks(), 22)!.ru.baby, 'BUNDLED 22 baby');
    await primePregnancyWeeksFromCache(cache);
    expect(weekContentFor(await loadPregnancyWeeks(), 22)!.ru.baby, 'SERVER 22 baby');
  });

  test('an empty cache is an ordinary first launch, not a degradation', () async {
    await primePregnancyWeeksFromCache(_MemoryCache());
    expect(weekContentFor(await loadPregnancyWeeks(), 22)!.ru.baby, 'BUNDLED 22 baby');
  });

  test('asks the public calendar route', () async {
    final t = _Transport(_payload([_week(22, 'SERVER 22 baby')]));
    await refreshPregnancyWeeksFromApi(api: ApiClient(t));
    expect(t.calls, ['/pregnancy/weeks']);
  });
}
