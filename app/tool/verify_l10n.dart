/// Pure-Dart verification of the localization core.
/// `dart run tool/verify_l10n.dart`
library;

import 'dart:io';
import '../lib/l10n/l10n.dart';
import '../lib/domain/child_tracker_state.dart';
import '../lib/core/geofence.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- Default locale is Russian ----
  _chk('default locale is Russian', resolveInitialLocale(null) == AppLocale.ru);
  _chk('saved pref wins (en)', resolveInitialLocale('en') == AppLocale.en);
  _chk('saved pref wins (kk)', resolveInitialLocale('kk') == AppLocale.kk);
  _chk('unknown pref -> Russian', resolveInitialLocale('fr') == AppLocale.ru);

  // ---- COVERAGE: every key defines all 3 languages ----
  final incomplete = allL10nKeys.where((k) => localesDefinedFor(k) != 3).toList();
  _chk('every key translated in ru+kk+en (${allL10nKeys.length} keys)', incomplete.isEmpty);
  if (incomplete.isNotEmpty) print('   missing: $incomplete');

  // ---- Lookups differ per language and are non-empty ----
  for (final key in ['nav_health', 'em_call_ambulance', 'metric_hr']) {
    final ru = const L10n(AppLocale.ru).t(key);
    final kk = const L10n(AppLocale.kk).t(key);
    final en = const L10n(AppLocale.en).t(key);
    _chk('$key non-empty in all langs', ru.isNotEmpty && kk.isNotEmpty && en.isNotEmpty);
    _chk('$key ru≠en (actually translated)', ru != en);
  }

  // ---- English strings match the original literals (keeps widget tests valid) ----
  const en = L10n(AppLocale.en);
  _chk('en em_title literal', en.t('em_title') == 'Urgent health alert');
  _chk('en em_not_emergency literal', en.t('em_not_emergency') == "This isn't an emergency");
  _chk('en db_empty_title literal', en.t('db_empty_title') == 'No readings yet');
  _chk('en metric_hr literal', en.metricLabel('hr') == 'Heart rate');

  // ---- Interpolation ----
  _chk('interpolate name', const L10n(AppLocale.ru).t('tr_title', {'name': 'Sultan'}).contains('Sultan'));
  _chk('interpolate ago minutes en', en.t('ago_min', {'n': 5}) == '5 min ago');
  _chk('ago() buckets: just now', en.ago(const Duration(seconds: 10)) == 'just now');
  _chk('ago() buckets: minutes', en.ago(const Duration(minutes: 5)) == '5 min ago');
  _chk('ago() ru minutes', const L10n(AppLocale.ru).ago(const Duration(minutes: 5)) == '5 мин назад');

  // ---- Triage code → message ----
  for (final code in triageCodesWithMessages) {
    _chk('triage $code has ru message', const L10n(AppLocale.ru).triageMessage(code).isNotEmpty);
  }
  _chk('unknown triage code -> generic', const L10n(AppLocale.ru).triageMessage('NOPE') ==
      const L10n(AppLocale.ru).t('EMERGENCY_GENERIC'));
  _chk('en PREECLAMPSIA_BP matches triage.dart literal',
      en.triageMessage('PREECLAMPSIA_BP') ==
          'High blood pressure detected — a warning sign of preeclampsia. Contact your doctor immediately.');

  // ---- Fallback: missing key returns the key ----
  _chk('missing key returns key', en.t('__nope__') == '__nope__');

  // ---- Tracking headline composition ----
  final school = Geofence.circle('s', 'School', const Coordinates(43.25, 76.95), 120);
  final now = DateTime.utc(2026, 7, 15, 9, 0);
  final atSchool = deriveChildStatus(
      childName: 'Sultan', location: school.center, updatedAt: now.subtract(const Duration(minutes: 1)), fences: [school], now: now);
  _chk('en headline at school', en.trackingHeadline(atSchool, 'Sultan', now) == 'Sultan is at School');
  _chk('ru headline at school', const L10n(AppLocale.ru).trackingHeadline(atSchool, 'Sultan', now).contains('Sultan'));

  final waiting = deriveChildStatus(childName: 'Sultan', location: null, updatedAt: null, fences: [school], now: now);
  _chk('ru waiting headline', const L10n(AppLocale.ru).trackingHeadline(waiting, 'Sultan', now).contains('Ожидание'));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
