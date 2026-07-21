/// What happens to saved data when it cannot be read, and when it cannot be
/// written.
///
/// Both paths used to end in silence. An unreadable config returned null, which
/// the app reads as "nothing saved" — so it showed first-run onboarding, and
/// onboarding's first save overwrote the very bytes that could not be read.
/// Whatever was wrong with them, they were the only copy of her history.
///
/// A failed WRITE was discarded by `unawaited`, so she carried on using an app
/// that was saving nothing and found out on the next launch.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/app_store.dart';
import 'package:fcs_app/data/persisted_config.dart';
import 'package:fcs_app/data/prefs_app_store.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';

const _key = 'fcs_app_config_v1';
const _quarantineKey = 'fcs_app_config_v1_unreadable';

/// A store whose writes always fail — a full disk, or prefs unavailable.
class _FailingStore implements AppStore {
  int attempts = 0;
  @override
  Future<PersistedConfig?> load() async => null;
  @override
  Future<void> save(PersistedConfig c) async {
    attempts++;
    throw const FileSystemException('no space left on device');
  }

  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a config that cannot be read', () {
    test('is set aside instead of being overwritten', () async {
      SharedPreferences.setMockInitialValues({_key: '{ this is not json'});
      final store = PrefsAppStore();

      expect(await store.load(), isNull); // the app will show onboarding
      expect(PrefsAppStore.lastLoadQuarantined, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_quarantineKey), '{ this is not json');

      // Now onboarding saves, as it would. The unreadable bytes must survive.
      await store.save(PersistedConfig(
        onboarded: true,
        locale: AppLocale.ru,
        profile: const UserProfile(displayName: 'Aigerim'),
        children: const [],
        devices: const [],
      ));
      expect(prefs.getString(_quarantineKey), '{ this is not json');
      expect(prefs.getString(_key), isNot('{ this is not json'));
    });

    test('keeps the FIRST failure, not a later emptier one', () async {
      // A second failure would be quarantining a blob onboarding has already
      // overwritten — newer, emptier, and no use to anyone.
      SharedPreferences.setMockInitialValues({_key: 'original-history'});
      final store = PrefsAppStore();
      await store.load();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, 'later-rubbish');
      await store.load();

      expect(prefs.getString(_quarantineKey), 'original-history');
    });

    test('erasing everything erases the copy too', () async {
      // "All data will be erased" has to include the copy the app made for
      // itself. Leaving her health history in a key she was never told about
      // would make that dialog a lie.
      SharedPreferences.setMockInitialValues({_key: 'unreadable'});
      final store = PrefsAppStore();
      await store.load();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_quarantineKey), isNotNull);

      await store.clear();
      expect(prefs.getString(_key), isNull);
      expect(prefs.getString(_quarantineKey), isNull);
      expect(PrefsAppStore.lastLoadQuarantined, isFalse);
    });

    test('a readable config is not quarantined and restores normally', () async {
      final good = PersistedConfig(
        onboarded: true,
        locale: AppLocale.ru,
        profile: const UserProfile(displayName: 'Aigerim'),
        children: const [],
        devices: const [],
      ).encode();
      SharedPreferences.setMockInitialValues({_key: good});

      final store = PrefsAppStore();
      final cfg = await store.load();
      expect(cfg?.profile.displayName, 'Aigerim');
      expect(PrefsAppStore.lastLoadQuarantined, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_quarantineKey), isNull);
    });

    test('nothing saved at all is not a failure', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PrefsAppStore().load(), isNull);
      expect(PrefsAppStore.lastLoadQuarantined, isFalse);
    });
  });

  group('a save that fails', () {
    test('is recorded rather than discarded', () async {
      // There is no crash reporting wired up, so the error log is the only
      // place a support conversation could start from.
      final store = _FailingStore();
      final c = AppController(persistStore: store);
      addTearDown(c.dispose);

      expect(c.errorLog.isEmpty, isTrue);
      c.updateProfile(const UserProfile(displayName: 'Aigerim'));
      c.flushPendingSave(); // the debounced write, now
      await Future<void>.delayed(Duration.zero);

      expect(store.attempts, greaterThan(0));
      expect(c.errorLog.isEmpty, isFalse, reason: 'a failed save left no trace');
      expect(c.errorLog.records.first.message, contains('no space left'));
    });

    test('does not take the app down with it', () async {
      // She keeps using the app; it simply is not saving. Throwing here would
      // turn a full disk into a crash.
      final c = AppController(persistStore: _FailingStore());
      addTearDown(c.dispose);
      c.updateProfile(const UserProfile(displayName: 'Aigerim'));
      c.flushPendingSave();
      await Future<void>.delayed(Duration.zero);
      expect(c.profile.displayName, 'Aigerim');
    });
  });
}
