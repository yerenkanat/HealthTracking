/// Screen 37 «Экстренная помощь» — where its scenarios come from, and the
/// address an ambulance is sent to.
///
/// The screen itself is driven from «Гиды» in guides_test.dart, because that is
/// the only thing that pushes it and a screen reachable only from a test is not
/// shipped. This file covers the two halves underneath it:
///
///   1. the three-layer ladder — bundled contract, cached response, server —
///      and the property that makes it worth having: nothing ever BLANKS a
///      scenario. This is the screen somebody opens because a child cannot
///      breathe.
///   2. `profile.address`, which had nowhere to live before this feature and
///      has to survive a reinstall, since the one moment she needs it is the
///      one moment she cannot be typing it in.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/data/emergency_help_repository.dart';
import 'package:fcs_app/domain/emergency_help.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';

/// A cache that lives in this test and nowhere else.
class _MemCache implements EmergencyHelpCache {
  String? value;
  int writes = 0;
  _MemCache([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
    writes++;
  }
}

class _FakeTransport implements HttpTransport {
  final int status;
  final String body;
  final List<String> gets = [];
  final List<Object> puts = [];
  _FakeTransport({this.status = 200, this.body = '{}'});
  @override
  Future<HttpResponse> get(String path) async {
    gets.add(path);
    return HttpResponse(status, body);
  }

  @override
  Future<HttpResponse> post(String path, Object body) async => const HttpResponse(201, '{}');
  @override
  Future<HttpResponse> put(String path, Object body) async {
    puts.add(body);
    return const HttpResponse(200, '{}');
  }

  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

/// The bundled baseline this test pretends the build shipped.
const _baseline = EmergencyHelp(
  version: 1,
  tel: '103',
  scenarios: [
    EmergencyScenario(
      id: 'bleeding',
      severity: EmergencySeverity.red,
      sort: 10,
      ru: EmergencyText(title: 'Кровотечение', what: 'Базовое «что»', todo: 'Базовое «что делать»'),
      kk: EmergencyText(title: 'Қан кету', what: 'Негізгі', todo: 'Негізгі'),
    ),
    EmergencyScenario(
      id: 'fever_newborn',
      severity: EmergencySeverity.amber,
      sort: 20,
      ru: EmergencyText(title: 'Температура', what: 'Базовое «что»', todo: 'Базовое «что делать»'),
      kk: EmergencyText(title: 'Қызу', what: 'Негізгі', todo: 'Негізгі'),
    ),
  ],
);

/// What a server response looks like: one scenario, rewritten.
String _serverJson({String todo = 'Новое «что делать»', String id = 'bleeding'}) => jsonEncode({
      'version': 9,
      'tel': '103',
      'scenarios': [
        {
          'id': id,
          'severity': 'red',
          'sort': 10,
          'ru': {'title': 'Кровотечение', 'what': 'Новое «что»', 'do': todo},
          'kk': {'title': 'Қан кету', 'what': 'Жаңа', 'do': 'Жаңа'},
        },
      ],
    });

void main() {
  setUp(() => debugSetEmergencyHelp(_baseline));

  group('the parse', () {
    test('a severity the app does not know reads as amber, never as nothing', () {
      // The stripe is the message. An unknown value must not produce a card
      // with no severity at all, and amber — «позвоните врачу сегодня» — is the
      // safe half of the two to guess at.
      final h = parseEmergencyHelp({
        'version': 1,
        'scenarios': [
          {'id': 'x', 'severity': 'chartreuse', 'sort': 1,
            'ru': {'title': 't', 'what': 'w', 'do': 'd'},
            'kk': {'title': 't', 'what': 'w', 'do': 'd'}},
        ],
      });
      expect(h.scenarios.single.severity, EmergencySeverity.amber);
    });

    test('scenariosBySeverity keeps reading order within a group', () {
      final red = scenariosBySeverity(_baseline.scenarios, EmergencySeverity.red);
      final amber = scenariosBySeverity(_baseline.scenarios, EmergencySeverity.amber);
      expect(red.map((s) => s.id), ['bleeding']);
      expect(amber.map((s) => s.id), ['fever_newborn']);
    });
  });

  group('asset → cache → server', () {
    test('with no cache and no server it is the bundled list', () async {
      final help = await loadEmergencyHelp();
      expect(help.scenarios.map((s) => s.id), ['bleeding', 'fever_newborn']);
      expect(help.scenarios.first.ru.todo, 'Базовое «что делать»');
    });

    test('a cached response is on screen before any request is made', () async {
      // A launch in a village with no signal shows the newest text this phone
      // ever received, not the text the build shipped with.
      await primeEmergencyHelpFromCache(_MemCache(_serverJson()));
      final help = await loadEmergencyHelp();
      expect(help.scenarios.first.ru.todo, 'Новое «что делать»');
    });

    test('a server response layers over the bundled list and is cached verbatim', () async {
      final cache = _MemCache();
      final t = _FakeTransport(body: _serverJson());
      final n = await refreshEmergencyHelpFromApi(api: ApiClient(t), cache: cache);

      expect(n, 1);
      expect(t.gets, ['/emergency-help']);
      // The exact bytes, so a field this build does not understand survives to
      // the next launch.
      expect(cache.value, _serverJson());
      final help = await loadEmergencyHelp();
      expect(help.scenarios.first.ru.todo, 'Новое «что делать»');
    });

    test('a response that covers ONE scenario does not blank the other', () async {
      // The property the whole ladder exists for. "Fetch and replace" here
      // means a woman opens this screen mid-emergency and finds one row.
      await refreshEmergencyHelpFromApi(api: ApiClient(_FakeTransport(body: _serverJson())));
      final help = await loadEmergencyHelp();
      expect(help.scenarios.map((s) => s.id), ['bleeding', 'fever_newborn']);
      expect(help.scenarios.last.ru.todo, 'Базовое «что делать»');
    });

    test('a scenario the contract does not have is not appended', () async {
      // Adding a scenario is a contract change. One invented by the server
      // would appear on a phone that has just fetched and vanish on one that
      // has not.
      await refreshEmergencyHelpFromApi(
          api: ApiClient(_FakeTransport(body: _serverJson(id: 'invented'))));
      final help = await loadEmergencyHelp();
      expect(help.scenarios.map((s) => s.id), ['bleeding', 'fever_newborn']);
    });

    test('a server that is down keeps what we have, and writes no cache', () async {
      final cache = _MemCache();
      final n = await refreshEmergencyHelpFromApi(
          api: ApiClient(_FakeTransport(status: 503)), cache: cache);
      expect(n, isNull);
      expect(cache.writes, 0);
      final help = await loadEmergencyHelp();
      expect(help.scenarios.first.ru.todo, 'Базовое «что делать»');
    });

    test('an unusable cached copy keeps the asset rather than emptying the screen',
        () async {
      await primeEmergencyHelpFromCache(_MemCache('{ not json at all'));
      final help = await loadEmergencyHelp();
      expect(help.scenarios, hasLength(2));
    });

    test('an empty server response is ignored, not adopted', () async {
      final n = await refreshEmergencyHelpFromApi(
          api: ApiClient(_FakeTransport(body: '{"version":9,"scenarios":[]}')));
      expect(n, isNull);
      expect((await loadEmergencyHelp()).scenarios, hasLength(2));
    });

    test('an edited scenario re-sorts the list, so triage order is editable', () async {
      await refreshEmergencyHelpFromApi(api: ApiClient(_FakeTransport(body: jsonEncode({
        'version': 9,
        'tel': '103',
        'scenarios': [
          {'id': 'bleeding', 'severity': 'red', 'sort': 99,
            'ru': {'title': 'Кровотечение', 'what': 'w', 'do': 'd'},
            'kk': {'title': 'Қан кету', 'what': 'w', 'do': 'd'}},
        ],
      }))));
      final help = await loadEmergencyHelp();
      expect(help.scenarios.map((s) => s.id), ['fever_newborn', 'bleeding']);
    });
  });

  group('the address an ambulance is sent to', () {
    test('rides the profile push, like the doctor number beside it', () async {
      final c = AppController(now: () => DateTime.utc(2026, 8, 12), locale: AppLocale.ru);
      addTearDown(c.dispose);
      final pushed = <UserProfile>[];
      c.attachProfileSync((p) async => pushed.add(p));

      c.updateProfile(const UserProfile(
        displayName: 'Aigerim',
        city: 'Алматы',
        address: 'мкр. Самал-2, д. 33, кв. 12, домофон 12К',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(pushed, hasLength(1));
      expect(pushed.first.address, 'мкр. Самал-2, д. 33, кв. 12, домофон 12К');
      expect(pushed.first.hasAddress, isTrue);
      // A city is not an address. Conflating them would put «Алматы» on the
      // dispatcher card as though somebody had typed it there.
      expect(pushed.first.city, 'Алматы');
    });

    test('is what PUT /profile actually sends', () async {
      // The push hook is only half the chain: the request body is the half
      // that reaches the server.
      final t = _FakeTransport();
      await ApiClient(t).putProfile(
        displayName: 'Aigerim',
        city: 'Алматы',
        address: '  мкр. Самал-2, д. 33  ',
      );
      final body = t.puts.single as Map<String, dynamic>;
      expect(body['address'], 'мкр. Самал-2, д. 33'); // trimmed
      expect(body['city'], 'Алматы');
    });

    test('an empty address is sent as null, not as an empty string', () async {
      // Null is «she declined», which screen 37 renders as her city plus
      // «Добавьте адрес». An empty string would render as a blank card.
      final t = _FakeTransport();
      await ApiClient(t).putProfile(displayName: 'Aigerim', address: '   ');
      expect((t.puts.single as Map<String, dynamic>)['address'], isNull);
    });

    test('survives the round trip through storage — which is what a reinstall is', () {
      const p = UserProfile(displayName: 'Aigerim', address: 'мкр. Самал-2, д. 33');
      final back = UserProfile.fromJson(p.toJson());
      expect(back.address, 'мкр. Самал-2, д. 33');
    });

    test('and comes back off the server on a new device', () {
      // What main.dart's _restore builds out of GET /profile.
      final c = AppController(now: () => DateTime.utc(2026, 8, 12), locale: AppLocale.ru);
      addTearDown(c.dispose);
      c.mergeRemoteProfile(const UserProfile(
        displayName: 'Aigerim',
        city: 'Алматы',
        address: 'мкр. Самал-2, д. 33',
        doctorPhone: '+77007654321',
      ));
      expect(c.profile.address, 'мкр. Самал-2, д. 33');
      expect(c.profile.doctorPhone, '+77007654321');
    });
  });
}
