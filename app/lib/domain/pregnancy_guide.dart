/// What a pregnant woman might feel at this stage, and when to call.
///
/// PURE Dart → verified by tool/verify_pregnancy_guide.dart.
///
/// WHY THIS EXISTS
///
/// The calendar already says a great deal about the BABY — its size, its
/// milestones, the week. It says almost nothing about HER: whether the nausea
/// is normal, when she might feel the first kicks, what the tightening in the
/// third trimester is. Flo's daily cards are built around exactly this, and its
/// absence is what makes our calendar feel clinical rather than companionable.
///
/// So this is two things, matching the postpartum guide on purpose: gentle
/// "what is usual around now" notes keyed to the week, and a short, always-shown
/// list of signs that mean "call your clinic". The reassurance is calm; the
/// warnings are not softened, and they point OUTWARD.
///
/// WHAT IT IS NOT
///
/// Not a diagnosis and not a rule. Pregnancies differ enormously — one woman
/// feels movement at 16 weeks and another at 22, and both are ordinary — so the
/// notes describe ranges and tendencies, never a schedule she is failing to
/// keep.
library;

/// Which thread a note belongs to, so the screen can badge it and a woman can
/// follow the one she is wondering about.
enum PregnancyArea {
  /// Physical changes and symptoms — nausea, tiredness, the bump.
  body,

  /// Managing the discomforts — eating, sleep position, swelling.
  comfort,

  /// The baby's movements — the flutters, then the pattern.
  movement,

  /// Mood and mind.
  mind,
}

/// One "what is usual around now" note, relevant across a window of weeks.
class StageNote {
  /// Stable id, and the l10n stem `preg_note_<id>`.
  final String id;
  final PregnancyArea area;

  /// The window, in completed weeks, inclusive, during which this is a "now"
  /// note. Windows overlap — several things are true in one week.
  final int fromWeek;
  final int toWeek;

  const StageNote({
    required this.id,
    required this.area,
    required this.fromWeek,
    required this.toWeek,
  });

  bool coversWeek(int week) => week >= fromWeek && week <= toWeek;
}

/// The stage notes, authored in rough week order. Windows overlap by design.
const List<StageNote> stageNotes = [
  // First trimester (about weeks 4–13).
  StageNote(id: 'nausea', area: PregnancyArea.body, fromWeek: 4, toWeek: 14),
  StageNote(id: 'tired', area: PregnancyArea.body, fromWeek: 4, toWeek: 13),
  StageNote(id: 'eating', area: PregnancyArea.comfort, fromWeek: 4, toWeek: 14),
  StageNote(id: 'emotions', area: PregnancyArea.mind, fromWeek: 4, toWeek: 40),

  // Second trimester (about weeks 14–27).
  StageNote(id: 'energy', area: PregnancyArea.body, fromWeek: 14, toWeek: 27),
  StageNote(id: 'first_movements', area: PregnancyArea.movement, fromWeek: 16, toWeek: 24),
  StageNote(id: 'ligament', area: PregnancyArea.comfort, fromWeek: 14, toWeek: 27),
  StageNote(id: 'bump', area: PregnancyArea.body, fromWeek: 16, toWeek: 30),

  // Third trimester (about weeks 28–40).
  StageNote(id: 'braxton', area: PregnancyArea.body, fromWeek: 28, toWeek: 40),
  StageNote(id: 'swelling', area: PregnancyArea.comfort, fromWeek: 28, toWeek: 40),
  StageNote(id: 'movement_pattern', area: PregnancyArea.movement, fromWeek: 25, toWeek: 40),
  StageNote(id: 'sleep_side', area: PregnancyArea.comfort, fromWeek: 28, toWeek: 40),
  StageNote(id: 'hospital_bag', area: PregnancyArea.mind, fromWeek: 32, toWeek: 40),
];

/// The signs that always mean "contact your clinic", at any week.
///
/// The obstetric red flags that are dangerous to wait on — bleeding, waters
/// breaking early, pre-eclampsia (headache, vision, swelling), severe pain, a
/// drop in the baby's movements, and infection. Each is an l10n stem
/// `preg_warn_<id>`. Never time-windowed and never reassured away.
const List<String> pregnancyWarnings = [
  'bleeding', // vaginal bleeding
  'fluid', // a gush or trickle of waters before labour
  'headache', // severe headache, vision changes, sudden swelling
  'pain', // severe or constant abdominal pain
  'movement', // baby moving noticeably less than usual
  'fever', // high fever, or burning when passing urine
];

/// The notes whose window contains [week], in authored order.
List<StageNote> notesForWeek(int week) =>
    [for (final n in stageNotes) if (n.coversWeek(week)) n];
