/// The last good `/vaccination/schedule` response, kept on the phone.
///
/// Split out of vaccination_schedule_repository.dart, which is compiled by
/// tool/verify_*.dart under a plain `dart run` VM: importing
/// shared_preferences there drags `dart:ui` in, and four runners — including
/// every AppController assertion in verify_persistence, verify_app,
/// verify_alerts and verify_chat — stopped compiling entirely. They ran zero
/// assertions for five days and CI stayed green-looking because the job it
/// gated was already red.
///
/// So the ladder is the same as everywhere else in this app: the pure file
/// declares the interface, this file is the only thing that touches a plugin,
/// and the repository re-exports it (conditionally — see the export at the
/// bottom of vaccination_schedule_repository.dart) so callers keep one import.
/// Mirrors shop_catalogue_cache.dart, which does the same for `JsonCache`.
///
/// shared_preferences, like every other durable thing in this app, so there is
/// no second persistence mechanism to reason about.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'vaccination_schedule_repository.dart';

/// [VaccinationScheduleCache] over shared_preferences — the same store the rest
/// of the app's durable state uses.
class PrefsVaccinationScheduleCache implements VaccinationScheduleCache {
  const PrefsVaccinationScheduleCache();

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(vaccinationScheduleCacheKey);
  }

  @override
  Future<void> write(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(vaccinationScheduleCacheKey, json);
  }
}
