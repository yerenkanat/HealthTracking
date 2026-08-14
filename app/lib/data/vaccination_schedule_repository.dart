/// Where the childhood immunisation calendar comes from.
///
/// Three layers, and the order matters:
///
///   1. `kzSchedule` in domain/vaccination.dart — the shared contract, compiled
///      into the build and held byte-identical to the server's copy by
///      tool/verify_vaccination_contract.dart. The BASELINE. Always present,
///      never replaced by an empty answer.
///   2. the last server response, cached in prefs, so a cold launch with no
///      signal still applies what the back office published.
///   3. `GET /vaccination/schedule`, fetched after first paint.
///
/// The reason this ladder is stricter here than anywhere else in the app: this
/// is the one screen whose job is to say «сводите ребёнка в поликлинику в
/// марте». A woman in a village with no signal must read the whole calendar,
/// not an apology — so the bundled schedule is on screen before any request is
/// made, and a failed refresh leaves it exactly where it was.
///
/// Until this file existed, `GET /vaccination/schedule` had no Dart caller at
/// all: the app read the compiled-in `kzSchedule` and a `const dueWindowMonths
/// = 1`, so the back office could move the second pneumococcal dose all day
/// (admin frames 15/15a/15b) and no phone ever found out. Deliberately mirrors
/// pregnancy_weeks_repository.dart: same ladder, same cache-the-exact-bytes
/// rule, same "a failure keeps what we have".
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vaccination.dart';
import 'api_client.dart';

/// Key under which the last good `/vaccination/schedule` response is cached.
const vaccinationScheduleCacheKey = 'vaccination_schedule_json';

/// Somewhere to keep the last good response. An interface rather than a direct
/// dependency on shared_preferences, so the layering is testable in plain Dart.
abstract class VaccinationScheduleCache {
  Future<String?> read();
  Future<void> write(String json);
}

/// [VaccinationScheduleCache] over shared_preferences — the same store the rest
/// of the app's durable state uses.
class PrefsVaccinationScheduleCache implements VaccinationScheduleCache {
  const PrefsVaccinationScheduleCache();

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(vaccinationScheduleCacheKey);

  @override
  Future<void> write(String json) async =>
      (await SharedPreferences.getInstance()).setString(vaccinationScheduleCacheKey, json);
}

/// One parsed answer: the calendar and the catch-up window that came with it.
class ServedVaccinationSchedule {
  final List<Vaccine> vaccines;
  final int dueWindowMonths;

  /// Moves whenever anything in the back office moves — an edit, an added
  /// vaccine, a change to the window. Kept so a stale copy is identifiable.
  final int version;

  const ServedVaccinationSchedule({
    required this.vaccines,
    required this.dueWindowMonths,
    required this.version,
  });
}

/// The shipped calendar, as the starting state. Never null, never empty.
const _bundled = ServedVaccinationSchedule(
  vaccines: kzSchedule,
  dueWindowMonths: dueWindowMonths,
  version: 0,
);

ServedVaccinationSchedule _current = _bundled;

/// Whether what is on screen came from the server (or its cache) rather than
/// from the build. The screen prints the revision differently for the two: a
/// two-year-old build's schedule should be identifiable as one.
bool _fromServer = false;

/// The calendar in use, right now, synchronously — the screens are built during
/// a frame and cannot await.
ServedVaccinationSchedule servedVaccinationSchedule() => _current;

/// The vaccines in use. Ordered by age, as both the contract and the server are.
List<Vaccine> servedVaccines() => _current.vaccines;

/// How long a vaccine reads as «пора» before it reads as «стоит наверстать».
/// The back office's number when there is one, the shipped default otherwise.
int servedDueWindowMonths() => _current.dueWindowMonths;

/// True once a server answer (live or cached) has been applied.
bool vaccinationScheduleIsFromServer() => _fromServer;

/// Apply the last cached server response, if there is one.
///
/// Called at startup BEFORE the network refresh, so a launch with no signal
/// still applies the newest calendar this phone ever received rather than
/// falling all the way back to the build's constant. Silent when there is no
/// cache — that is an ordinary first launch, not a degradation.
Future<void> primeVaccinationScheduleFromCache(VaccinationScheduleCache cache) async {
  try {
    final raw = await cache.read();
    if (raw == null) return;
    final parsed = parseServedVaccinationSchedule(raw);
    if (parsed == null) return;
    _current = parsed;
    _fromServer = true;
  } catch (e) {
    debugPrint('vaccination schedule: cached copy unusable, keeping the bundled calendar — $e');
  }
}

/// Fetch `/vaccination/schedule` and adopt it.
///
/// Returns how many vaccines the server sent, or null if it could not be
/// reached or answered with something unusable — in which case the caller keeps
/// whatever it already had, which is the entire point of loading the constant
/// first. A failure is logged and never surfaces as an empty screen.
///
/// Adopt-whole rather than merge-by-key, unlike the pregnancy calendar. The
/// server's answer IS contract-plus-overrides — it merges the shipped entries
/// in itself and falls back to the contract when its own database is
/// unreachable — so layering here would be a second merge over the first, and
/// the one thing it could add is resurrecting a vaccine the back office has
/// deliberately retired.
Future<int?> refreshVaccinationScheduleFromApi({
  required ApiClient api,
  VaccinationScheduleCache? cache,
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final raw = await api.fetchVaccinationScheduleJson().timeout(timeout);
    final parsed = parseServedVaccinationSchedule(raw);
    if (parsed == null) return null;
    // The exact bytes, not a re-encode, so a field this build does not
    // understand still survives to the next launch.
    unawaited(cache?.write(raw));
    _current = parsed;
    _fromServer = true;
    return parsed.vaccines.length;
  } catch (e) {
    debugPrint('vaccination schedule: refresh failed, keeping what we have — $e');
    return null;
  }
}

/// Parse one `/vaccination/schedule` payload, or null if it is unusable.
///
/// "Unusable" is deliberately strict, because the fallback is a correct
/// calendar and the alternative is a wrong one:
///
///   * no `vaccines` array, or an empty one — a schedule with no vaccines is
///     never a real answer, and adopting it would blank the screen;
///   * an entry with no id, or an age outside 0..216 months — the server's own
///     CHECK agrees, and a vaccine at month -3 would sort above birth;
///   * a `dueWindowMonths` outside 1..12 falls back to the shipped default
///     rather than rejecting the whole calendar: a bad window is one wrong
///     boundary, a rejected payload is sixteen stale rows.
ServedVaccinationSchedule? parseServedVaccinationSchedule(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = decoded.cast<String, dynamic>();
    final list = map['vaccines'];
    if (list is! List || list.isEmpty) return null;

    final vaccines = <Vaccine>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final e = entry.cast<String, dynamic>();
      final id = (e['id'] as String?)?.trim() ?? '';
      final atMonth = _asInt(e['atMonth']);
      if (id.isEmpty || atMonth == null || atMonth < 0 || atMonth > 216) continue;
      vaccines.add(Vaccine(
        id: id,
        atMonth: atMonth,
        dose: _asInt(e['dose']),
        ru: _asText(e['ru']),
        kk: _asText(e['kk']),
        ruNote: _asText(e['ruNote']),
        kkNote: _asText(e['kkNote']),
        added: e['added'] == true,
      ));
    }
    if (vaccines.isEmpty) return null;
    // The screen groups by age and relies on insertion order for its timeline.
    // The server sorts, but a client that trusts a remote sort silently
    // reorders the day the server stops doing it.
    vaccines.sort((a, b) => a.atMonth.compareTo(b.atMonth));

    final window = _asInt(map['dueWindowMonths']);
    return ServedVaccinationSchedule(
      vaccines: vaccines,
      dueWindowMonths:
          (window != null && window >= 1 && window <= 12) ? window : dueWindowMonths,
      version: _asInt(map['version']) ?? 0,
    );
  } catch (e) {
    debugPrint('vaccination schedule: could not parse a payload — $e');
    return null;
  }
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Text the back office actually wrote. Whitespace-only is nothing written.
String? _asText(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

/// Test seam: adopt a schedule directly, without a server.
void debugSetVaccinationSchedule(ServedVaccinationSchedule schedule) {
  _current = schedule;
  _fromServer = true;
}

/// Test seam: back to the bundled calendar and the shipped window, so a test
/// starts from the state of a phone that has never had a signal.
void debugResetVaccinationSchedule() {
  _current = _bundled;
  _fromServer = false;
}
