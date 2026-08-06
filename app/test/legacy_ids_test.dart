/// Re-issuing ids that could never sync, without losing anything.
///
/// Onboarding used to mint 'child-1', 'home' and 'school'. The server needs a
/// UUID for both a child and a geofence, so all three were refused with a 400
/// that nothing surfaced. Fixing onboarding helps the next install; every
/// handset that already has one needs its ids re-issued.
///
/// The risk in doing that is not the rename — it is everything that POINTS at
/// a child id. Battery, battery history, growth, the newborn log, vaccinations
/// and a paired tag are all keyed by it, so a migration that renamed only the
/// child would silently blank her baby's weight chart and vaccination record.
/// That would be a worse bug than the one being fixed, so it is checked here
/// one table at a time.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/app_store.dart';
import 'package:fcs_app/data/persisted_config.dart';
import 'package:fcs_app/domain/child_growth.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/legacy_ids.dart';
import 'package:fcs_app/l10n/l10n.dart';

/// Predictable ids, so a failure names the table rather than a random UUID.
String Function() sequence() {
  var n = 0;
  return () => 'aaaaaaaa-bbbb-cccc-dddd-${(++n).toString().padLeft(12, '0')}';
}

const legacyChild = ChildProfile(
  id: 'child-1',
  name: 'Сұлтан',
  geofences: [],
);

Geofence circle(String id, String name) =>
    Geofence.circle(id, name, const Coordinates(43.238949, 76.889709), 100);

void main() {
  group('which ids get re-issued', () {
    test('the ones the server would refuse', () {
      final r = reissueUnsyncableIds([legacyChild], newId: sequence());

      expect(r.children.single.id, isNot('child-1'));
      expect(isSyncableId(r.children.single.id), isTrue);
      expect(r.childIds, {'child-1': r.children.single.id});
    });

    test('and only those — a UUID is left exactly as it is', () {
      // Re-issuing one would orphan the copy the server already holds and
      // duplicate the child in the back office: the opposite of the point.
      const already = ChildProfile(
          id: '11111111-2222-3333-4444-555555555555', name: 'Аружан', geofences: []);
      final r = reissueUnsyncableIds([already], newId: sequence());

      expect(r.children.single.id, already.id);
      expect(r.isEmpty, isTrue, reason: 'nothing changed, so nothing should be re-saved');
    });

    test('the zones every alert is built on', () {
      final child = ChildProfile(
        id: 'child-1',
        name: 'Сұлтан',
        geofences: [circle('home', 'Дом'), circle('school', 'Школа')],
      );
      final r = reissueUnsyncableIds([child], newId: sequence());

      final zones = r.children.single.geofences;
      expect(zones.map((z) => z.name), ['Дом', 'Школа'], reason: 'the zones are hers, not ours');
      for (final z in zones) {
        expect(isSyncableId(z.id), isTrue);
      }
      expect(zones[0].id, isNot(zones[1].id));
      // The shape and the place have to survive the rename, or her home moves.
      expect(zones[0].center, const Coordinates(43.238949, 76.889709));
      expect(zones[0].radiusM, 100);
    });

    test('everything the mother typed survives', () {
      final child = ChildProfile(
        id: 'child-1',
        name: 'Сұлтан',
        dateOfBirth: DateTime(2019, 3, 8),
        gender: Gender.boy,
        photoPath: '/photos/sultan.jpg',
        tagId: 'AA:BB:CC:DD:EE:FF',
        geofences: [circle('home', 'Дом')],
      );
      final out = reissueUnsyncableIds([child], newId: sequence()).children.single;

      expect(out.name, 'Сұлтан');
      expect(out.dateOfBirth, DateTime(2019, 3, 8));
      expect(out.gender, Gender.boy);
      expect(out.photoPath, '/photos/sultan.jpg');
      expect(out.tagId, 'AA:BB:CC:DD:EE:FF');
    });

    test('running it twice changes nothing the second time', () {
      final once = reissueUnsyncableIds([legacyChild], newId: sequence());
      final twice = reissueUnsyncableIds(once.children, newId: sequence());

      expect(twice.isEmpty, isTrue);
      expect(twice.children.single.id, once.children.single.id);
    });
  });

  group('what points at a child id', () {
    test('a side table follows the child it is about', () {
      // The failure this guards: her baby's weight chart and vaccination
      // record going blank on upgrade, because the rows were keyed by an id
      // that no longer exists.
      final renamed = {'child-1': 'aaaaaaaa-bbbb-cccc-dddd-000000000001'};

      expect(remapKeys({'child-1': 84}, renamed),
          {'aaaaaaaa-bbbb-cccc-dddd-000000000001': 84});
      expect(remapKeys({'child-1': ['bcg', 'dtp']}, renamed),
          {'aaaaaaaa-bbbb-cccc-dddd-000000000001': ['bcg', 'dtp']});
    });

    test('a child that was not renamed keeps its rows', () {
      final renamed = {'child-1': 'aaaaaaaa-bbbb-cccc-dddd-000000000001'};
      final out = remapKeys({'child-1': 1, 'untouched-uuid': 2}, renamed);
      expect(out['untouched-uuid'], 2);
    });

    test('nothing to rename is left untouched, same instance', () {
      final table = {'a': 1};
      expect(identical(remapKeys(table, const {}), table), isTrue);
    });

    test('a tag follows the child it is strapped to', () {
      // Leaving it on the old id detaches the tracker from the child, which
      // looks exactly like a tracker that stopped working.
      const tag = PairedDevice(
          id: 'AA:BB', name: 'Трекер', kind: DeviceKind.tag, childId: 'child-1');
      final out = remapDeviceChildIds(
          [tag], {'child-1': 'aaaaaaaa-bbbb-cccc-dddd-000000000001'});

      expect(out.single.childId, 'aaaaaaaa-bbbb-cccc-dddd-000000000001');
      expect(out.single.id, 'AA:BB', reason: 'the device id is physical and does not change');
    });

    test("a band, which belongs to no child, is untouched", () {
      const band = PairedDevice(id: 'CC:DD', name: 'Часы', kind: DeviceKind.band);
      final out = remapDeviceChildIds([band], {'child-1': 'x'});
      expect(out.single.childId, isNull);
    });
  });

  /// The migration where it actually runs: a real controller reading a real
  /// saved config, which is the only place the seven side tables are wired
  /// together.
  group('a phone that already has a legacy child', () {
    test('comes back with a syncable child and none of her data lost', () async {
      final store = InMemoryAppStore();
      await store.save(PersistedConfig(
        onboarded: true,
        locale: AppLocale.ru,
        profile: const UserProfile(),
        children: [
          ChildProfile(
            id: 'child-1',
            name: 'Сұлтан',
            dateOfBirth: DateTime(2019, 3, 8),
            geofences: [circle('home', 'Дом'), circle('school', 'Школа')],
          ),
        ],
        devices: const [
          PairedDevice(id: 'AA:BB', name: 'Трекер', kind: DeviceKind.tag, childId: 'child-1'),
        ],
        childBattery: const {'child-1': 84},
        childGrowth: {
          'child-1': [GrowthPoint(at: DateTime(2026, 1, 1), weightKg: 22.5)],
        },
        vaccinesDone: const {'child-1': ['bcg']},
      ));

      // Read the same way a launch reads it.
      final loaded = AppController(persistStore: store);
      addTearDown(loaded.dispose);
      await loaded.restore();

      final child = loaded.children.single;
      expect(isSyncableId(child.id), isTrue, reason: 'she still cannot sync');
      expect(child.name, 'Сұлтан');
      expect(child.dateOfBirth, DateTime(2019, 3, 8));
      for (final z in child.geofences) {
        expect(isSyncableId(z.id), isTrue, reason: '${z.name} still cannot sync');
      }

      // And everything that pointed at the old id came with her.
      expect(loaded.batteryFor(child.id), 84, reason: 'the tracker battery was orphaned');
      expect(loaded.growthFor(child.id), hasLength(1), reason: 'the weight chart went blank');
      expect(loaded.vaccinesDoneFor(child.id), contains('bcg'),
          reason: 'the vaccination record went blank');
      expect(loaded.devices.single.childId, child.id,
          reason: 'the tag came unstrapped from the child');
      expect(loaded.selectedChild?.id, child.id);
    });

    test('the migration is written back, not just held in memory', () async {
      // It used to survive only until some unrelated edit happened to trigger
      // a save, so two shapes of the truth sat on disk indefinitely. Every
      // read went through the migrated state, so it worked — and it is the
      // kind of works that stops working.
      final store = InMemoryAppStore();
      await store.save(PersistedConfig(
        onboarded: true,
        locale: AppLocale.ru,
        profile: const UserProfile(),
        children: const [ChildProfile(id: 'child-1', name: 'Сұлтан', geofences: [])],
        devices: const [],
        dayLogs: const {
          '2026-05-21T00:00:00.000Z':
              DayLog(date: '2026-05-21T00:00:00.000Z', flow: Flow.medium),
        },
      ));

      final first = AppController(persistStore: store);
      await first.restore();
      await first.dispose();

      // Read the raw saved config back: the old shapes must be gone from disk.
      final saved = (await store.load())!;
      expect(saved.children.single.id, isNot('child-1'));
      expect(saved.dayLogs.keys, ['2026-05-21']);
      expect(saved.dayLogs['2026-05-21']!.date, '2026-05-21');
    });

    test('a config with nothing to migrate is not rewritten', () async {
      // Saving on every launch would churn storage for no reason, and would
      // hide whether the migration ever actually ran.
      final store = _CountingStore(InMemoryAppStore());
      await store.save(const PersistedConfig(
        onboarded: true,
        locale: AppLocale.ru,
        profile: UserProfile(),
        children: [
          ChildProfile(id: '11111111-2222-3333-4444-555555555555', name: 'Аружан', geofences: []),
        ],
        devices: [],
      ));
      store.saves = 0;

      final c = AppController(persistStore: store);
      await c.restore();
      await c.dispose();

      expect(store.saves, 0, reason: 'nothing needed migrating, so nothing should be saved');
    });
  });

  /// Day logs written by an older build.
  ///
  /// Found on a real handset: some entries are keyed `2026-05-21` and others
  /// `2026-05-21T00:00:00.000Z`. The server requires yyyy-MM-dd, so every ISO
  /// one was refused with a 400 — months of her cycle diary that could never
  /// reach the back office, reported once per log as an uncaught async error
  /// nobody was reading.
  group('day logs an older build wrote', () {
    test('an ISO timestamp becomes the day it was recorded on', () {
      expect(normaliseDayKey('2026-05-21T00:00:00.000Z'), '2026-05-21');
      // Not converted across zones: that would move an entry over midnight and
      // rewrite the day she recorded something on.
      expect(normaliseDayKey('2026-05-21T23:30:00.000+06:00'), '2026-05-21');
    });

    test('a key already in the right shape is untouched', () {
      expect(normaliseDayKey('2026-05-21'), '2026-05-21');
    });

    test('something that is not a date at all is dropped, not sent', () {
      expect(normaliseDayKey('yesterday'), isNull);
      expect(normaliseDayKey(''), isNull);
    });

    test('the value carries the day too, and is rewritten with it', () {
      // A DayLog holds its date twice. Fixing only the key would send a body
      // the server refuses for exactly the same reason.
      final out = normaliseDayKeys<String>(
        {'2026-05-21T00:00:00.000Z': 'old'},
        (v, day) => '$v@$day',
      );
      expect(out, {'2026-05-21': 'old@2026-05-21'});
    });

    test('when both forms of a day exist, the current one wins', () {
      final out = normaliseDayKeys<String>(
        {'2026-05-21': 'plain', '2026-05-21T00:00:00.000Z': 'legacy'},
        (v, day) => v,
      );
      expect(out, {'2026-05-21': 'plain'});
    });

    test('and the same holds whichever order they are stored in', () {
      final out = normaliseDayKeys<String>(
        {'2026-05-21T00:00:00.000Z': 'legacy', '2026-05-21': 'plain'},
        (v, day) => v,
      );
      expect(out, {'2026-05-21': 'plain'});
    });
  });

  group('what counts as syncable', () {
    test('the ids the server actually accepts', () {
      expect(isSyncableId('11111111-2222-3333-4444-555555555555'), isTrue);
      expect(isSyncableId('AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'), isTrue);
    });

    test('and the ones it does not', () {
      for (final bad in [
        'child-1',
        'home',
        '',
        '11111111-2222-3333-4444', // truncated
        '11111111-2222-3333-4444-55555555555g', // one bad character
      ]) {
        expect(isSyncableId(bad), isFalse, reason: '$bad would be refused with a 400');
      }
    });
  });
}

/// Counts saves, so "nothing to migrate writes nothing" can be asserted.
class _CountingStore implements AppStore {
  final AppStore inner;
  int saves = 0;
  _CountingStore(this.inner);

  @override
  Future<PersistedConfig?> load() => inner.load();

  @override
  Future<void> save(PersistedConfig cfg) {
    saves++;
    return inner.save(cfg);
  }

  @override
  Future<void> clear() => inner.clear();
}
