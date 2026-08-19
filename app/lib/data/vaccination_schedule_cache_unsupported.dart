/// The stand-in for [PrefsVaccinationScheduleCache] where there is no Flutter.
///
/// vaccination_schedule_repository.dart is reached from app_controller.dart, so
/// the pure-Dart verification runners compile it under a `dart run` VM that has
/// no `dart:ui` and therefore no shared_preferences. The repository picks
/// between this file and vaccination_schedule_cache.dart with a conditional
/// export, which keeps the repository pure while leaving `main.dart`'s single
/// `import 'data/vaccination_schedule_repository.dart'` resolving to the real,
/// prefs-backed cache in every build that actually ships.
///
/// It throws rather than quietly returning null. Nothing off-Flutter has any
/// business caching a schedule, and a cache that silently forgets what it was
/// asked to keep is the failure mode this repository exists to prevent — a
/// phone with no signal falling back to the compiled-in calendar while the
/// code reports success.
library;

import 'vaccination_schedule_repository.dart';

/// See the library comment: constructing this is fine (main.dart does it as a
/// `const`), using it is not.
class PrefsVaccinationScheduleCache implements VaccinationScheduleCache {
  const PrefsVaccinationScheduleCache();

  @override
  Future<String?> read() async => throw UnsupportedError(
      'PrefsVaccinationScheduleCache needs shared_preferences, which needs Flutter. '
      'Pass your own VaccinationScheduleCache outside a Flutter build.');

  @override
  Future<void> write(String json) async => throw UnsupportedError(
      'PrefsVaccinationScheduleCache needs shared_preferences, which needs Flutter. '
      'Pass your own VaccinationScheduleCache outside a Flutter build.');
}
