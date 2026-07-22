/// Pure-Dart verification of the localization core.
/// `dart run tool/verify_l10n.dart`
library;

import 'dart:io';
import '../lib/domain/child_development.dart';
import '../lib/domain/vaccination.dart';
import '../lib/domain/postpartum.dart';
import '../lib/domain/pregnancy_guide.dart';
import '../lib/domain/fetal_development.dart';
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

  // ---- Placeholders survive translation ----
  //
  // t() substitutes {name}, {n}, {m} into the string. A translation that drops
  // one loses whatever it carried, silently and only in that language: "мин"
  // where the number should be, "Привет," with no name. Nothing throws, the
  // sentence still renders, and it is wrong only for the people reading it in
  // the language nobody on the team is checking.
  //
  // Clean today across all 774 keys; this keeps it that way.
  Set<String> placeholders(String s) =>
      RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

  final mismatched = <String>[];
  for (final key in allL10nKeys) {
    final ru = placeholders(const L10n(AppLocale.ru).t(key));
    final kk = placeholders(const L10n(AppLocale.kk).t(key));
    final en = placeholders(const L10n(AppLocale.en).t(key));
    if (!_sameSet(ru, kk) || !_sameSet(ru, en)) {
      mismatched.add('$key (ru=$ru kk=$kk en=$en)');
    }
  }
  _chk('every language carries the same placeholders (${mismatched.length} do not)',
      mismatched.isEmpty);
  for (final m in mismatched.take(10)) {
    print('   $m');
  }

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

  // ---- Child age formatting ----
  _chk('childAge newborn', en.childAge(0) == 'Newborn');
  _chk('childAge months', en.childAge(8) == '8 mo');
  _chk('childAge year+months', en.childAge(14) == '1y 2m');
  _chk('childAge years', en.childAge(30) == '2 yrs');

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

  // The clock-disagreement sentence must reach every language, not just the
  // English reference in child_tracker_state. Russian is the app default, so
  // "only English got the honest wording" is the failure that matters most.
  final skewed = deriveChildStatus(
      childName: 'Sultan', location: school.center, updatedAt: now.add(const Duration(hours: 3)), fences: [school], now: now);
  for (final loc in AppLocale.values) {
    final l = L10n(loc);
    final line = l.trackingHeadline(skewed, 'Sultan', now);
    // Must be the skew sentence itself. Asserting merely that it avoids
    // "School" was too weak to fail: with the bug restored the headline fell
    // through to the stale branch, which also omits the zone — it just ended
    // "last seen just now". The check has to name the sentence it wants.
    _chk('${loc.name} headline is the clock-disagreement sentence',
        line == l.t('tr_clock_skew', {'name': 'Sultan'}) && line != 'tr_clock_skew');
    _chk('${loc.name} skew line never reads as freshly seen',
        !line.contains(l.t('ago_just_now')) && !line.contains('{'));
  }
  // agoIfKnown is the honest one; ago() is for callers that clamp deliberately.
  _chk('agoIfKnown refuses a future timestamp', en.agoIfKnown(const Duration(hours: -3)) == null);
  _chk('ago() still answers for a clamping caller', en.ago(Duration.zero) == 'just now');

  // ---- Every key the UI asks for must exist ----
  //
  // L10n.t falls back to the KEY when it finds no row, so a typo or a deleted
  // entry does not fail — it renders `repeat_title_bp` on screen, in place of a
  // sentence, to the user. The existing checks all run the other way: they
  // prove every key in the catalogue is translated. Nothing proved the UI only
  // asks for keys that are in it.
  {
    final known = allL10nKeys.toSet();
    final uiDir = Directory.fromUri(Platform.script.resolve('../lib'));
    final missing = <String>[];
    var literals = 0;

    // t('literal') / t("literal") — the composed ones (t('metric_$k')) are
    // covered by the family check below, since a regex cannot resolve them.
    final call = RegExp(r'''\bt\(\s*(['"])([a-z][a-z0-9_]*)\1''');

    for (final f in uiDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('l10n.dart')) continue; // the catalogue itself
      final name = f.path.replaceAll(r'\', '/').split('/').last;
      for (final line in f.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        for (final m in call.allMatches(line)) {
          literals++;
          final key = m.group(2)!;
          if (!known.contains(key)) missing.add('$name: $key');
        }
      }
    }

    _chk('the scan found real t() calls ($literals)', literals > 100);
    if (missing.isNotEmpty) {
      print('\n  Keys the UI asks for that the catalogue does not have:');
      for (final m in missing) {
        print('    $m');
      }
      print('');
    }
    _chk('every key the UI asks for exists (${missing.length} missing)', missing.isEmpty);

    // Families composed at runtime: t('metric_$key'), t('mood_${m.name}') and
    // friends. A regex cannot resolve those, so each family is listed with the
    // suffixes the code can actually produce, and every combination checked.
    // A new enum value without a matching row would otherwise ship the raw key.
    const families = <String, List<String>>{
      'metric_': ['hr', 'spo2', 'temp', 'systolic', 'diastolic'],
      'mood_': ['happy', 'calm', 'anxious', 'tired', 'sad'],
      'sym_': ['allGood', 'cramps', 'spotting', 'headache', 'nausea', 'swelling'],
      'flow_': ['light', 'medium', 'heavy'],
      'gender_': ['boy', 'girl'],
      'fresh_': ['live', 'recent', 'stale'],
      'em_reading_': ['bp', 'temp', 'spo2', 'hr'],
      'repeat_title_': ['bp', 'fever', 'spo2', 'hr'],
      'zone_loc_': ['denied', 'denied_forever', 'failed'],
      'lesson_': ['play', 'pause', 'play_failed'],
    };
    final missingFamily = <String>[];
    for (final e in families.entries) {
      for (final suffix in e.value) {
        if (!known.contains('${e.key}$suffix')) missingFamily.add('${e.key}$suffix');
      }
    }
    _chk('every runtime-composed key exists (${missingFamily.length} missing'
        '${missingFamily.isEmpty ? '' : ': ${missingFamily.join(", ")}'})',
        missingFamily.isEmpty);
  }

  // ---- Development milestones carry their own strings ----
  //
  // These keys are built from the milestone id at render time — `dev_$id` and
  // `dev_${id}_note` — so the scan above, which reads literal t('...') calls
  // out of the source, cannot see them. Without this, adding a milestone and
  // forgetting its strings ships the raw key to a parent's screen.
  {
    final known = allL10nKeys.toSet();
    final missing = <String>[];
    for (final m in devMilestones) {
      for (final key in ['dev_${m.id}', 'dev_${m.id}_note']) {
        if (!known.contains(key)) missing.add(key);
      }
    }
    _chk('every milestone has a title and a note (${devMilestones.length} checked)',
        missing.isEmpty);
    if (missing.isNotEmpty) print('    missing: ${missing.join(', ')}');

    // And every area label, for the same reason.
    final areaMissing = [
      for (final a in DevArea.values)
        if (!known.contains('dev_area_${a.name}')) 'dev_area_${a.name}'
    ];
    _chk('every development area has a label', areaMissing.isEmpty);

    // Translated, not just present. A key that exists only in English renders
    // English to a Russian-speaking mother, which the app's default locale
    // makes the common case rather than the edge one.
    var untranslated = 0;
    for (final m in devMilestones) {
      for (final key in ['dev_${m.id}', 'dev_${m.id}_note']) {
        for (final loc in AppLocale.values) {
          final v = L10n(loc).t(key);
          if (v == key || v.trim().isEmpty) untranslated++;
        }
      }
    }
    _chk('and all three languages have real text ($untranslated blanks)', untranslated == 0);

    // Same story for vaccines: `vac_$id` and `vac_${id}_note` are composed at
    // render time, so a vaccine added without strings would put a raw key on
    // the screen a parent takes to the polyclinic.
    final vacMissing = <String>[];
    for (final id in kzSchedule.map((v) => v.id).toSet()) {
      for (final key in ['vac_$id', 'vac_${id}_note']) {
        if (!known.contains(key)) vacMissing.add(key);
      }
    }
    _chk('every vaccine has a name and a note', vacMissing.isEmpty);
    if (vacMissing.isNotEmpty) print('    missing: ${vacMissing.join(', ')}');

    var vacBlank = 0;
    for (final id in kzSchedule.map((v) => v.id).toSet()) {
      for (final key in ['vac_$id', 'vac_${id}_note']) {
        for (final loc in AppLocale.values) {
          final v = L10n(loc).t(key);
          if (v == key || v.trim().isEmpty) vacBlank++;
        }
      }
    }
    _chk('and in all three languages ($vacBlank blanks)', vacBlank == 0);

    // Postpartum: `pp_note_<id>`, `pp_warn_<id>` and `pp_area_<area>` are all
    // composed at render time. A recovery note or a warning sign added without
    // strings would put a raw key on the recovery screen — and the warning list
    // is the last place that can be allowed to happen.
    final ppMissing = <String>[
      for (final n in recoveryNotes)
        if (!known.contains('pp_note_${n.id}')) 'pp_note_${n.id}',
      for (final id in warningSigns)
        if (!known.contains('pp_warn_$id')) 'pp_warn_$id',
      for (final a in RecoveryArea.values)
        if (!known.contains('pp_area_${a.name}')) 'pp_area_${a.name}',
    ];
    _chk('every recovery note, warning and area has strings', ppMissing.isEmpty);
    if (ppMissing.isNotEmpty) print('    missing: ${ppMissing.join(', ')}');

    var ppBlank = 0;
    final ppKeys = <String>[
      for (final n in recoveryNotes) 'pp_note_${n.id}',
      for (final id in warningSigns) 'pp_warn_$id',
      for (final a in RecoveryArea.values) 'pp_area_${a.name}',
    ];
    for (final key in ppKeys) {
      for (final loc in AppLocale.values) {
        final v = L10n(loc).t(key);
        if (v == key || v.trim().isEmpty) ppBlank++;
      }
    }
    _chk('and postpartum strings are all translated ($ppBlank blanks)', ppBlank == 0);

    // Pregnancy guide: `preg_note_<id>`, `preg_warn_<id>` and `preg_area_<area>`
    // are composed at render time, same as the postpartum ones.
    final pregMissing = <String>[
      for (final n in stageNotes)
        if (!known.contains('preg_note_${n.id}')) 'preg_note_${n.id}',
      for (final id in pregnancyWarnings)
        if (!known.contains('preg_warn_$id')) 'preg_warn_$id',
      for (final a in PregnancyArea.values)
        if (!known.contains('preg_area_${a.name}')) 'preg_area_${a.name}',
    ];
    _chk('every stage note, warning and area has strings', pregMissing.isEmpty);
    if (pregMissing.isNotEmpty) print('    missing: ${pregMissing.join(', ')}');

    var pregBlank = 0;
    final pregKeys = <String>[
      for (final n in stageNotes) 'preg_note_${n.id}',
      for (final id in pregnancyWarnings) 'preg_warn_$id',
      for (final a in PregnancyArea.values) 'preg_area_${a.name}',
    ];
    for (final key in pregKeys) {
      for (final loc in AppLocale.values) {
        final v = L10n(loc).t(key);
        if (v == key || v.trim().isEmpty) pregBlank++;
      }
    }
    _chk('and pregnancy-guide strings are all translated ($pregBlank blanks)', pregBlank == 0);

    // Fetal development: `fet_<id>` is composed at render time from the
    // highlight id, so a highlight added without strings would show a raw key.
    final fetMissing = [
      for (final h in fetalHighlights)
        if (!known.contains('fet_${h.id}')) 'fet_${h.id}'
    ];
    _chk('every fetal highlight has a string', fetMissing.isEmpty);
    if (fetMissing.isNotEmpty) print('    missing: ${fetMissing.join(', ')}');

    var fetBlank = 0;
    for (final h in fetalHighlights) {
      for (final loc in AppLocale.values) {
        final v = L10n(loc).t('fet_${h.id}');
        if (v == 'fet_${h.id}' || v.trim().isEmpty) fetBlank++;
      }
    }
    _chk('and every fetal highlight is translated ($fetBlank blanks)', fetBlank == 0);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
