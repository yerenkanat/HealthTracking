/// Safe infant sleep — the reduce-the-risk-of-SIDS guidance.
///
/// PURE Dart → verified by tool/verify_safe_sleep.dart.
///
/// WHY THIS EXISTS
///
/// Sudden infant death is rare, and most of what lowers the risk is a handful
/// of simple, well-established things about where and how a baby sleeps. They
/// are easy to get slightly wrong when exhausted — a pillow left in the cot, an
/// hour of shared sleep on the sofa — and a companion app for the first months
/// is exactly where the reminder belongs. The newborn log is where a tired
/// parent records sleep; the reference sits one tap from it.
///
/// WHAT IT IS
///
/// Two short lists — what to DO and what to AVOID — drawn from the standard
/// public-health guidance (back to sleep, own firm flat surface, room-share not
/// bed-share, nothing soft in the cot, no overheating, no smoke). Deliberately
/// short: a list of twenty rules is one nobody reads.
///
/// Each rule carries a CODE the UI localizes (`ss_<id>`).
library;

/// Whether a rule is something to do, or something to avoid — so the screen can
/// split them into two clearly different lists rather than one flat wall.
enum SleepRuleKind { follow, avoid }

class SleepRule {
  final String id;
  final SleepRuleKind kind;
  const SleepRule({required this.id, required this.kind});
}

/// The safe-sleep rules. Short and ordered by how much they matter.
const List<SleepRule> safeSleepRules = [
  // Do.
  SleepRule(id: 'back', kind: SleepRuleKind.follow), // on the back, every sleep
  SleepRule(id: 'firm', kind: SleepRuleKind.follow), // firm flat surface, fitted sheet
  SleepRule(id: 'own_bed', kind: SleepRuleKind.follow), // own cot in your room
  SleepRule(id: 'clear', kind: SleepRuleKind.follow), // nothing else in the cot
  SleepRule(id: 'pacifier', kind: SleepRuleKind.follow), // a dummy at sleep, once feeding is settled

  // Avoid.
  SleepRule(id: 'bedshare', kind: SleepRuleKind.avoid), // sharing a surface, sofa worst of all
  SleepRule(id: 'soft', kind: SleepRuleKind.avoid), // pillows, bumpers, loose blankets, toys
  SleepRule(id: 'overheat', kind: SleepRuleKind.avoid), // too warm, head covered
  SleepRule(id: 'smoke', kind: SleepRuleKind.avoid), // smoke anywhere near the baby
];

/// The rules to follow, in order.
List<SleepRule> get sleepDos =>
    [for (final r in safeSleepRules) if (r.kind == SleepRuleKind.follow) r];

/// The rules to avoid, in order.
List<SleepRule> get sleepAvoids =>
    [for (final r in safeSleepRules) if (r.kind == SleepRuleKind.avoid) r];
