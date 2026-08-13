/// Screen 37 «Экстренная помощь» — the scenarios, and what to do about each.
///
/// PURE Dart (parse + lookup) → verified by tool/verify_emergency_help_contract.dart.
///
/// The data is the shared contract (packages/contract/emergency_help.json), the
/// same file the backend serves at GET /emergency-help and the admin panel
/// edits (frame 16b). The app bundles a copy as an asset so the screen works
/// offline; the verify runner asserts the copy matches the contract so they
/// cannot drift.
///
/// [EmergencySeverity] is the only field here that is not prose. `red` means
/// dial 103 now and `amber` means call the clinic today — the screen paints the
/// left border from it, and an unknown value falls back to `amber` rather than
/// to nothing, because a scenario with no stripe reads as ordinary advice.
///
/// The catalogue carries ru + kk only. For the app's third language (en) we
/// fall back to ru, exactly as the pregnancy calendar does: a blank instruction
/// is worse than a Russian sentence a bilingual reader can still act on.
library;

enum EmergencySeverity {
  /// «Звоните 103 сейчас».
  red,

  /// «Позвоните врачу сегодня».
  amber,
}

EmergencySeverity severityFromName(String? s) =>
    s == 'red' ? EmergencySeverity.red : EmergencySeverity.amber;

/// Who a scenario is written for.
///
/// Three of the shipped nine are pregnancy triage by their own words — «после
/// 20 недель», «после 28 недель». They are the reason this field exists: a
/// woman who is not expecting was being shown preeclampsia signs that cannot
/// apply to her, mixed in with the ones that can, on the screen where reading
/// one row too many costs time.
///
/// [all] is the default and the fallback for anything unrecognised. The failure
/// this enum must never cause is HIDING first aid: an unknown audience shows
/// the scenario to everyone, which is the safe direction to be wrong in.
enum EmergencyAudience {
  /// Anyone holding the phone.
  all,

  /// Only while she is expecting.
  pregnancy,
}

EmergencyAudience audienceFromName(String? s) =>
    s == 'pregnancy' ? EmergencyAudience.pregnancy : EmergencyAudience.all;

class EmergencyText {
  /// What she recognises herself by — the row's headline.
  final String title;

  /// «Что происходит?» — the signs, in plain words.
  final String what;

  /// What to do about it, and what not to do.
  final String todo;

  const EmergencyText({required this.title, required this.what, required this.todo});

  factory EmergencyText.fromJson(Map<String, dynamic> j) => EmergencyText(
        title: (j['title'] as String?)?.trim() ?? '',
        what: (j['what'] as String?)?.trim() ?? '',
        // `do` in the contract — a Dart reserved word, so the field is `todo`
        // here and the JSON key stays what every other layer already reads.
        todo: (j['do'] as String?)?.trim() ?? '',
      );

  bool get isEmpty => title.isEmpty && what.isEmpty && todo.isEmpty;
}

class EmergencyScenario {
  final String id;
  final EmergencySeverity severity;
  final int sort;

  /// Who it is written for. Defaults to [EmergencyAudience.all] — including for
  /// a payload from an older server that does not send the field at all.
  final EmergencyAudience audience;
  final EmergencyText ru;
  final EmergencyText kk;

  const EmergencyScenario({
    required this.id,
    required this.severity,
    required this.sort,
    this.audience = EmergencyAudience.all,
    required this.ru,
    required this.kk,
  });

  factory EmergencyScenario.fromJson(Map<String, dynamic> j) => EmergencyScenario(
        id: (j['id'] as String?)?.trim() ?? '',
        severity: severityFromName(j['severity'] as String?),
        sort: (j['sort'] as num?)?.toInt() ?? 0,
        audience: audienceFromName(j['audience'] as String?),
        ru: EmergencyText.fromJson((j['ru'] as Map).cast<String, dynamic>()),
        kk: EmergencyText.fromJson((j['kk'] as Map).cast<String, dynamic>()),
      );

  /// The text for a locale code ('ru' | 'kk' | 'en'), en → ru fallback.
  EmergencyText textFor(String localeCode) => localeCode == 'kk' ? kk : ru;
}

/// The whole list, plus the number to dial.
class EmergencyHelp {
  final int version;

  /// The ambulance number, from the contract rather than a literal in the UI —
  /// so the one place it can be wrong is the one place it is edited.
  final String tel;
  final List<EmergencyScenario> scenarios;

  const EmergencyHelp({required this.version, required this.tel, required this.scenarios});

  static const empty = EmergencyHelp(version: 0, tel: '103', scenarios: []);

  bool get isEmpty => scenarios.isEmpty;
}

/// Parse the whole file. Tolerant per scenario: a malformed entry is skipped
/// rather than losing the file — the same "one bad field costs that field, not
/// everything" rule the app uses for persistence, and it matters most here,
/// where the alternative is an empty emergency screen.
EmergencyHelp parseEmergencyHelp(Map<String, dynamic> json) {
  final raw = (json['scenarios'] as List?) ?? const [];
  final out = <EmergencyScenario>[];
  for (final s in raw) {
    if (s is! Map) continue;
    try {
      final parsed = EmergencyScenario.fromJson(s.cast<String, dynamic>());
      // An entry with no id cannot be merged or reported against, and one with
      // no Russian title draws a blank row.
      if (parsed.id.isEmpty || parsed.ru.title.isEmpty) continue;
      out.add(parsed);
    } catch (_) {
      // skip a bad row
    }
  }
  out.sort((a, b) {
    final bySort = a.sort.compareTo(b.sort);
    return bySort != 0 ? bySort : a.id.compareTo(b.id);
  });
  final tel = (json['tel'] as String?)?.trim();
  return EmergencyHelp(
    version: (json['version'] as num?)?.toInt() ?? 0,
    tel: tel == null || tel.isEmpty ? '103' : tel,
    scenarios: out,
  );
}

/// The red ones first, in reading order. Used by the screen's section and by
/// the verify runner, so «сначала красные» is one rule in one place.
List<EmergencyScenario> scenariosBySeverity(
  List<EmergencyScenario> all,
  EmergencySeverity severity,
) =>
    [for (final s in all) if (s.severity == severity) s];

/// The scenarios that apply to the person reading, in the file's own order.
///
/// Expecting: everything. A pregnant woman may also have a toddler who has just
/// swallowed a battery, so nothing is taken away from her — the pregnancy
/// scenarios are ADDED to the rest.
///
/// Not expecting: the pregnancy-only ones are dropped. «После 20 недель» and
/// «после 28 недель» are instructions she cannot act on, and every one of them
/// sits between her and the row she opened the screen for.
///
/// Postpartum is deliberately NOT a pregnancy audience: a haemorrhage or an
/// infection happens after the due date has been cleared, so those scenarios
/// stay [EmergencyAudience.all] and reach her either way.
List<EmergencyScenario> scenariosForAudience(
  List<EmergencyScenario> all, {
  required bool pregnant,
}) =>
    pregnant
        ? all
        : [for (final s in all) if (s.audience != EmergencyAudience.pregnancy) s];
