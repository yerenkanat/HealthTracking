/// Week-by-week pregnancy calendar content — what the baby is doing, what the
/// mother may feel, and what to do, for each gestational week, in ru + kk.
///
/// PURE Dart (parse + lookup) → verified by tool/verify_pregnancy_weeks_contract.dart.
///
/// The data is the shared contract (packages/contract/pregnancy_weeks.json), the
/// same file the backend serves at GET /pregnancy/weeks and the admin panel
/// renders. The app bundles a copy as an asset so the week screen works offline;
/// the verify runner asserts the copy matches the contract so they cannot drift.
///
/// The calendar carries ru + kk only (the source spreadsheet). For the app's
/// third language (en) we fall back to ru, since a clinical blank is worse than
/// a Russian sentence a bilingual user can still read.
library;

class PregnancyWeekText {
  final String baby;
  final String you;
  final String recommend;
  const PregnancyWeekText({required this.baby, required this.you, required this.recommend});

  factory PregnancyWeekText.fromJson(Map<String, dynamic> j) => PregnancyWeekText(
        baby: (j['baby'] as String?)?.trim() ?? '',
        you: (j['you'] as String?)?.trim() ?? '',
        recommend: (j['recommend'] as String?)?.trim() ?? '',
      );

  bool get isEmpty => baby.isEmpty && you.isEmpty && recommend.isEmpty;
}

class PregnancyWeekContent {
  final int week;
  final String lengthCm; // free text: "0,02", "—", "25–156"
  final String hcg;
  final PregnancyWeekText ru;
  final PregnancyWeekText kk;

  const PregnancyWeekContent({
    required this.week,
    required this.lengthCm,
    required this.hcg,
    required this.ru,
    required this.kk,
  });

  factory PregnancyWeekContent.fromJson(Map<String, dynamic> j) => PregnancyWeekContent(
        week: (j['week'] as num).toInt(),
        lengthCm: (j['lengthCm'] as String?)?.trim() ?? '',
        hcg: (j['hcg'] as String?)?.trim() ?? '',
        ru: PregnancyWeekText.fromJson((j['ru'] as Map).cast<String, dynamic>()),
        kk: PregnancyWeekText.fromJson((j['kk'] as Map).cast<String, dynamic>()),
      );

  /// The text for a locale code ('ru' | 'kk' | 'en'), en → ru fallback.
  PregnancyWeekText textFor(String localeCode) => localeCode == 'kk' ? kk : ru;

  bool get hasLength => lengthCm.isNotEmpty && lengthCm != '—';
}

/// Parse the whole calendar file. Tolerant per-week: a malformed week is skipped
/// rather than losing the file — the same "one bad field costs that field, not
/// everything" rule the app uses for persistence.
List<PregnancyWeekContent> parsePregnancyWeeks(Map<String, dynamic> json) {
  final raw = (json['weeks'] as List?) ?? const [];
  final out = <PregnancyWeekContent>[];
  for (final w in raw) {
    if (w is! Map) continue;
    try {
      out.add(PregnancyWeekContent.fromJson(w.cast<String, dynamic>()));
    } catch (_) {
      // skip a bad row
    }
  }
  out.sort((a, b) => a.week.compareTo(b.week));
  return out;
}

/// The content for [week], clamped into the covered range so an early or overdue
/// week still returns the nearest real entry. Null only for an empty list.
PregnancyWeekContent? weekContentFor(List<PregnancyWeekContent> weeks, int week) {
  if (weeks.isEmpty) return null;
  final lo = weeks.first.week, hi = weeks.last.week;
  final w = week < lo ? lo : (week > hi ? hi : week);
  for (final e in weeks) {
    if (e.week == w) return e;
  }
  return weeks.first;
}
