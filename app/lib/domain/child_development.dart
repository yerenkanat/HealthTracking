/// What a baby is likely to be doing, and roughly when.
///
/// PURE Dart → verified by tool/verify_child_development.dart.
///
/// WHAT THIS IS NOT
///
/// It is not a test, a score, or a schedule a child is supposed to keep. Every
/// entry is a RANGE, because the spread between healthy children is enormous:
/// most walk somewhere between 9 and 18 months, and both ends of that are
/// ordinary. A single "walks at 12 months" would tell the mother of a
/// perfectly healthy 14-month-old that her child is late.
///
/// So each milestone carries three ages:
///
///   * [typicalFrom] / [typicalTo] — where most children land. This is what the
///     timeline draws.
///   * [askByMonth] — the age by which NOT doing it is worth raising with a
///     doctor. Not a diagnosis; a prompt to ask. Drawn from the ranges the WHO
///     and CDC publish for exactly this purpose, which are deliberately late:
///     the point is to catch the child who needs help without alarming the
///     families of the many who are simply taking their time.
///
/// The distance between "most children by now" and "worth asking" is the whole
/// value here. An app that shows only the first turns every slow month into
/// worry; one that shows only the second is useless.
library;

/// What kind of change a milestone is. Used to group the timeline, and to let
/// a parent follow the thread they care about.
enum DevArea {
  /// Rolling, sitting, crawling, standing, walking.
  motor,

  /// Grasping, passing objects hand to hand, pointing, first spoon.
  fine,

  /// Cooing, babbling, first words, two-word phrases.
  speech,

  /// Smiling, recognising faces, playing, waving.
  social,

  /// Teeth.
  teeth,

  /// Feeding changes — first solids, cup, self-feeding.
  feeding,
}

/// One expected change.
class DevMilestone {
  /// Stable id, and the l10n key stem: `dev_<id>` for the title and
  /// `dev_<id>_note` for the sentence under it.
  final String id;
  final DevArea area;

  /// Months, inclusive. [typicalTo] may equal [typicalFrom] for a point event.
  final int typicalFrom;
  final int typicalTo;

  /// The age by which its absence is worth a conversation with a doctor.
  ///
  /// Null where there is no meaningful threshold — the first tooth can
  /// genuinely arrive at 3 months or at 15, and neither is a concern on its
  /// own, so inventing a number here would manufacture worry rather than
  /// prevent it.
  final int? askByMonth;

  const DevMilestone({
    required this.id,
    required this.area,
    required this.typicalFrom,
    required this.typicalTo,
    this.askByMonth,
  });

  /// Midpoint of the typical range, for ordering and for placing a marker.
  double get typicalMid => (typicalFrom + typicalTo) / 2;
}

/// The table. Ordered by when it typically starts.
///
/// Ages are in COMPLETED months since birth. Deliberately not exhaustive: a
/// list of two hundred items is a document, not a screen. These are the
/// changes parents actually watch for and ask about.
const List<DevMilestone> devMilestones = [
  // ---- The first quarter ----
  DevMilestone(id: 'lifts_head', area: DevArea.motor, typicalFrom: 1, typicalTo: 3, askByMonth: 4),
  DevMilestone(id: 'social_smile', area: DevArea.social, typicalFrom: 1, typicalTo: 3, askByMonth: 4),
  DevMilestone(id: 'follows_objects', area: DevArea.social, typicalFrom: 2, typicalTo: 4, askByMonth: 5),
  DevMilestone(id: 'coos', area: DevArea.speech, typicalFrom: 2, typicalTo: 4, askByMonth: 5),
  DevMilestone(id: 'holds_head_steady', area: DevArea.motor, typicalFrom: 3, typicalTo: 5, askByMonth: 6),

  // ---- Half a year ----
  DevMilestone(id: 'grasps', area: DevArea.fine, typicalFrom: 3, typicalTo: 5, askByMonth: 7),
  DevMilestone(id: 'rolls_over', area: DevArea.motor, typicalFrom: 4, typicalTo: 6, askByMonth: 7),
  DevMilestone(id: 'laughs', area: DevArea.social, typicalFrom: 3, typicalTo: 5, askByMonth: 7),
  DevMilestone(id: 'first_solids', area: DevArea.feeding, typicalFrom: 6, typicalTo: 6),
  DevMilestone(id: 'first_tooth', area: DevArea.teeth, typicalFrom: 6, typicalTo: 10),
  DevMilestone(id: 'sits_supported', area: DevArea.motor, typicalFrom: 5, typicalTo: 7, askByMonth: 9),
  DevMilestone(id: 'babbles', area: DevArea.speech, typicalFrom: 5, typicalTo: 8, askByMonth: 10),

  // ---- Toward one ----
  DevMilestone(id: 'sits_alone', area: DevArea.motor, typicalFrom: 6, typicalTo: 9, askByMonth: 10),
  DevMilestone(id: 'passes_objects', area: DevArea.fine, typicalFrom: 6, typicalTo: 9, askByMonth: 10),
  DevMilestone(id: 'stranger_awareness', area: DevArea.social, typicalFrom: 6, typicalTo: 10),
  DevMilestone(id: 'crawls', area: DevArea.motor, typicalFrom: 7, typicalTo: 11),
  DevMilestone(id: 'pincer_grip', area: DevArea.fine, typicalFrom: 8, typicalTo: 11, askByMonth: 12),
  DevMilestone(id: 'pulls_to_stand', area: DevArea.motor, typicalFrom: 8, typicalTo: 11, askByMonth: 13),
  DevMilestone(id: 'waves_bye', area: DevArea.social, typicalFrom: 8, typicalTo: 12, askByMonth: 15),
  DevMilestone(id: 'cup', area: DevArea.feeding, typicalFrom: 8, typicalTo: 12),
  DevMilestone(id: 'first_words', area: DevArea.speech, typicalFrom: 10, typicalTo: 14, askByMonth: 16),
  DevMilestone(id: 'stands_alone', area: DevArea.motor, typicalFrom: 10, typicalTo: 14, askByMonth: 16),

  // ---- The second year ----
  DevMilestone(id: 'first_steps', area: DevArea.motor, typicalFrom: 9, typicalTo: 15, askByMonth: 18),
  DevMilestone(id: 'self_feeds_spoon', area: DevArea.feeding, typicalFrom: 12, typicalTo: 18),
  DevMilestone(id: 'points', area: DevArea.social, typicalFrom: 12, typicalTo: 15, askByMonth: 18),
  DevMilestone(id: 'walks_well', area: DevArea.motor, typicalFrom: 13, typicalTo: 18, askByMonth: 20),
  DevMilestone(id: 'molars', area: DevArea.teeth, typicalFrom: 13, typicalTo: 19),
  DevMilestone(id: 'several_words', area: DevArea.speech, typicalFrom: 15, typicalTo: 20, askByMonth: 24),
  DevMilestone(id: 'runs', area: DevArea.motor, typicalFrom: 18, typicalTo: 24),
  DevMilestone(id: 'two_word_phrases', area: DevArea.speech, typicalFrom: 18, typicalTo: 26, askByMonth: 30),
  DevMilestone(id: 'full_milk_teeth', area: DevArea.teeth, typicalFrom: 24, typicalTo: 33),
  DevMilestone(id: 'stairs', area: DevArea.motor, typicalFrom: 22, typicalTo: 30),
];

/// Where a milestone sits relative to a child of [ageMonths].
enum DevStatus {
  /// Its typical window has not opened yet.
  ahead,

  /// Inside the window — this is what to watch for now.
  now,

  /// The window has passed. NOT "late": most of these have no threshold at all,
  /// and passing the typical range is ordinary.
  passed,

  /// Past the age where its absence is worth raising with a doctor.
  worthAsking,
}

/// Classify [m] for a child of [ageMonths].
///
/// [worthAsking] is deliberately separate from [passed]: the difference between
/// "most children are doing this by now" and "this is worth a conversation" is
/// the whole point of the table, and collapsing them would turn every ordinary
/// slow month into an alarm.
DevStatus statusFor(DevMilestone m, int ageMonths) {
  if (ageMonths < m.typicalFrom) return DevStatus.ahead;
  if (ageMonths <= m.typicalTo) return DevStatus.now;
  final ask = m.askByMonth;
  if (ask != null && ageMonths >= ask) return DevStatus.worthAsking;
  return DevStatus.passed;
}

/// Milestones whose typical window contains [ageMonths] — "right now".
List<DevMilestone> milestonesNow(int ageMonths) =>
    [for (final m in devMilestones) if (statusFor(m, ageMonths) == DevStatus.now) m];

/// The next [limit] milestones that have not opened yet, soonest first.
List<DevMilestone> milestonesAhead(int ageMonths, {int limit = 3}) {
  final ahead = [for (final m in devMilestones) if (m.typicalFrom > ageMonths) m]
    ..sort((a, b) => a.typicalFrom.compareTo(b.typicalFrom));
  return ahead.take(limit).toList();
}

/// How far back the "worth asking" list reaches.
///
/// Without a window this returned every threshold ever passed: at 18 months
/// that is NINETEEN items, starting with "lifts their head". The app does not
/// know what the child has actually done, so it would be handing a parent a
/// page-long list of things their walking, talking toddler obviously does —
/// which is both useless and frightening.
///
/// Six months of recently-crossed thresholds is a conversation to have at the
/// next appointment. The whole list is a diagnosis nobody made.
const worthAskingWindowMonths = 6;

/// And a hard cap on top of the window.
///
/// The window alone still produced seven items at 18 months, because the table
/// is dense there. Seven things to raise is not a conversation, it is a
/// worry-list — and the app cannot know that the child does not already do
/// every one of them.
const worthAskingMax = 5;

/// Milestones whose "ask a doctor" age was crossed RECENTLY, most recent first.
///
/// The screen shows these quietly, last, and worded as a prompt rather than a
/// finding. A parent reading this is often already worried.
///
/// Most-recent-first because that is the end of the list most likely to still
/// be true: a threshold crossed last month is a better question than one
/// crossed five months ago, which the child has probably met since.
List<DevMilestone> worthAsking(int ageMonths) {
  final recent = [
    for (final m in devMilestones)
      if (statusFor(m, ageMonths) == DevStatus.worthAsking &&
          ageMonths - m.askByMonth! <= worthAskingWindowMonths)
        m
  ]..sort((a, b) => b.askByMonth!.compareTo(a.askByMonth!));
  return recent.take(worthAskingMax).toList();
}

/// Whole months between [birth] and [now], by the calendar rather than by
/// elapsed days — the same reason daysBetween exists.
int ageInMonths(DateTime birth, DateTime now) {
  var months = (now.year - birth.year) * 12 + (now.month - birth.month);
  if (now.day < birth.day) months--;
  return months < 0 ? 0 : months;
}

/// The milestones grouped by area, each ordered by when it starts. For a
/// timeline that lets a parent follow one thread — teeth, or words — rather
/// than reading everything at once.
Map<DevArea, List<DevMilestone>> byArea() {
  final out = <DevArea, List<DevMilestone>>{};
  for (final m in devMilestones) {
    (out[m.area] ??= []).add(m);
  }
  for (final list in out.values) {
    list.sort((a, b) => a.typicalFrom.compareTo(b.typicalFrom));
  }
  return out;
}
