/// Child safety advisor — turns a child's age (from date of birth) and current
/// tracking status into a few plain, practical, age-appropriate safety tips.
/// This is the child-safety counterpart to HealthAdvisor: data-grounded guidance,
/// never alarmist. PURE Dart → unit-testable via `dart run tool/verify_safety.dart`.
///
/// Each tip carries a CODE the UI localizes (ru/kk/en), so no language is baked
/// into the logic. Ordering: watch-first, then a reassuring status note, then the
/// age-band tips.
library;

import 'child_tracker_state.dart' show Freshness;

enum AgeBand { infant, toddler, preschool, schoolAge, preteen }

enum TipTone { positive, info, watch }

class SafetyTip {
  final String code; // localized by the UI, e.g. 'CS_TODDLER_WATER'
  final TipTone tone;
  const SafetyTip(this.code, this.tone);
}

/// Age band from whole months of age (see ChildProfile.ageInMonths).
AgeBand ageBandFor(int months) {
  if (months < 12) return AgeBand.infant;
  if (months < 36) return AgeBand.toddler;
  if (months < 60) return AgeBand.preschool;
  if (months < 144) return AgeBand.schoolAge;
  return AgeBand.preteen;
}

/// Two age-specific tip codes per band.
List<String> _ageTips(AgeBand band) => switch (band) {
      AgeBand.infant => const ['CS_INFANT_SLEEP', 'CS_INFANT_CARSEAT'],
      AgeBand.toddler => const ['CS_TODDLER_WATER', 'CS_TODDLER_CHOKING'],
      AgeBand.preschool => const ['CS_PRESCHOOL_ROAD', 'CS_PRESCHOOL_IDENTITY'],
      AgeBand.schoolAge => const ['CS_SCHOOL_ROUTE', 'CS_SCHOOL_CHECKIN'],
      AgeBand.preteen => const ['CS_PRETEEN_ONLINE', 'CS_PRETEEN_LOCATION'],
    };

/// Generate safety tips for a child.
///
/// [ageMonths] — whole months of age, or null if no DOB is set.
/// [currentZone] — the geofence the child is inside right now, if any.
/// [freshness] — how fresh the last location fix is.
/// [hasLocation] — whether any location fix exists yet.
List<SafetyTip> generateChildTips({
  int? ageMonths,
  String? currentZone,
  Freshness freshness = Freshness.stale,
  bool hasLocation = false,
}) {
  final watch = <SafetyTip>[];
  final positive = <SafetyTip>[];
  final info = <SafetyTip>[];

  // ---- Status-driven (contextual) ----
  if (hasLocation) {
    if (freshness == Freshness.stale) {
      watch.add(const SafetyTip('CS_DELAYED', TipTone.watch));
    } else if (currentZone != null) {
      positive.add(const SafetyTip('CS_AT_ZONE', TipTone.positive));
    } else {
      info.add(const SafetyTip('CS_ON_MOVE', TipTone.info));
    }
  }

  // ---- Age-appropriate ----
  if (ageMonths == null) {
    info.add(const SafetyTip('CS_NO_DOB', TipTone.info));
  } else {
    for (final code in _ageTips(ageBandFor(ageMonths))) {
      info.add(SafetyTip(code, TipTone.info));
    }
  }

  return [...watch, ...positive, ...info];
}
