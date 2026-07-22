/// The state antenatal-care schedule, as an algorithm keyed to the week.
///
/// PURE Dart → verified by tool/verify_antenatal_protocol.dart.
///
/// WHY THIS EXISTS
///
/// Kazakhstan's Ministry of Health publishes a clinical protocol for antenatal
/// care ("Антенатальный уход", Clinical Protocol №248, 2025 revision). It is the
/// document every doctor in the country follows: a standard plan of AT LEAST
/// EIGHT visits at defined gestational weeks, and — this is the part a woman
/// never gets to see — exactly which examinations, laboratory tests, screenings
/// and prophylaxis belong to each visit. A rhesus-negative mother is given
/// anti-D at 28–30 weeks; the glucose-tolerance test happens between 24 and 28;
/// the anomaly-scan window is 19+0 to 21+0 and closes. Miss the window and the
/// check is simply gone.
///
/// The calendar already tells her how big the baby is this week. It has never
/// told her what her own care schedule is — so she takes it on trust that the
/// clinic is on top of it. This turns the government protocol into something she
/// can hold: which visit is due now, which is next, and precisely what that
/// visit is for. It lets her walk in already knowing what should happen, and
/// notice if it doesn't.
///
/// WHAT IT IS NOT
///
/// Not a substitute for the clinic and not a diagnosis. The schedule is the
/// STANDARD plan; the protocol itself says the frequency and content change the
/// moment a risk factor or complication appears. So the app frames this as "what
/// the standard plan includes", always pointing back to her own doctor, never
/// as a checklist she is passing or failing.
///
/// SOURCE
/// docs/Антенатальный уход.docx — Клинические протоколы МЗ РК 2025, Протокол
/// №248, "Таблица 1. Содержание антенатального ухода" (the eight-visit table),
/// plus the monitoring, screening and prophylaxis sections that surround it.
library;

/// The kind of thing a visit item is, so the screen can group and badge it the
/// way the protocol itself is organised (Консультирование / Обследование /
/// Лабораторные / Инструментальные / Лечебно-профилактические).
enum AntenatalCategory {
  /// Counselling and information — risk review, danger signs, what comes next.
  counsel,

  /// A physical examination or measurement done at the visit.
  exam,

  /// A laboratory test — blood, urine, swabs.
  lab,

  /// An instrumental screening — ultrasound, ECG.
  imaging,

  /// A treatment or preventive measure — folic acid, anti-D, maternity leave.
  prophylaxis,
}

/// One line of a visit: a stable id (l10n stem `an_item_<id>`) and its category.
///
/// [risk] marks an item the protocol applies only to a risk group (aspirin for
/// pre-eclampsia risk, the glucose-tolerance test for diabetes risk factors,
/// anti-D for rhesus-negative mothers). The screen shows these as
/// "if it applies to you" so a woman without the risk is not alarmed that it was
/// not done to her.
class AntenatalItem {
  /// Stable id, and the l10n stem `an_item_<id>`.
  final String id;
  final AntenatalCategory category;

  /// True when the protocol scopes this item to a risk group rather than every
  /// pregnancy.
  final bool risk;

  const AntenatalItem(this.id, this.category, {this.risk = false});
}

/// One of the eight standard visits: its number, its gestational-week window
/// (completed weeks, inclusive), and the items the protocol assigns to it.
class AntenatalVisit {
  /// 1..8, in the order the protocol numbers them.
  final int number;

  /// The window in completed weeks, inclusive. A single-week visit (the 30-week
  /// visit) has [fromWeek] == [toWeek].
  final int fromWeek;
  final int toWeek;

  /// The visit's contents, in protocol order (counsel → exam → lab → imaging →
  /// prophylaxis is the tendency, but authored order is kept).
  final List<AntenatalItem> items;

  const AntenatalVisit({
    required this.number,
    required this.fromWeek,
    required this.toWeek,
    required this.items,
  });

  bool coversWeek(int week) => week >= fromWeek && week <= toWeek;
}

/// The eight-visit standard plan, transcribed from "Таблица 1. Содержание
/// антенатального ухода". Windows are the protocol's ("в сроке 10–12 недель"
/// etc.); the final visit runs to 40 weeks + 6 days, held here as week 40.
const List<AntenatalVisit> antenatalVisits = [
  // I посещение — 10–12 недель. The big first visit: dating, full work-up.
  AntenatalVisit(number: 1, fromWeek: 10, toWeek: 12, items: [
    AntenatalItem('history_risk', AntenatalCategory.counsel),
    AntenatalItem('danger_signs', AntenatalCategory.counsel),
    AntenatalItem('schedule_plan', AntenatalCategory.counsel),
    AntenatalItem('bmi', AntenatalCategory.exam),
    AntenatalItem('bp_pulse', AntenatalCategory.exam),
    AntenatalItem('legs_varicose', AntenatalCategory.exam),
    AntenatalItem('breast_exam', AntenatalCategory.exam),
    AntenatalItem('gyn_exam', AntenatalCategory.exam),
    AntenatalItem('us_dating', AntenatalCategory.imaging),
    AntenatalItem('ecg', AntenatalCategory.imaging, risk: true),
    AntenatalItem('cbc', AntenatalCategory.lab),
    AntenatalItem('blood_glucose', AntenatalCategory.lab),
    AntenatalItem('urinalysis', AntenatalCategory.lab),
    AntenatalItem('blood_type_rh', AntenatalCategory.lab),
    AntenatalItem('urine_culture', AntenatalCategory.lab),
    AntenatalItem('cervical_cytology', AntenatalCategory.lab),
    AntenatalItem('hiv', AntenatalCategory.lab),
    AntenatalItem('syphilis', AntenatalCategory.lab),
    AntenatalItem('hep_b', AntenatalCategory.lab),
    AntenatalItem('serum_markers', AntenatalCategory.lab),
    AntenatalItem('therapist', AntenatalCategory.counsel),
    AntenatalItem('folic_acid', AntenatalCategory.prophylaxis),
    AntenatalItem('aspirin', AntenatalCategory.prophylaxis, risk: true),
    AntenatalItem('calcium', AntenatalCategory.prophylaxis, risk: true),
  ]),

  // II посещение — 16–20 недель. Review the first-visit results; fundal height
  // and the anomaly scan begin.
  AntenatalVisit(number: 2, fromWeek: 16, toWeek: 20, items: [
    AntenatalItem('screening_review', AntenatalCategory.counsel),
    AntenatalItem('birth_school', AntenatalCategory.counsel),
    AntenatalItem('bp_pulse', AntenatalCategory.exam),
    AntenatalItem('legs_varicose', AntenatalCategory.exam),
    AntenatalItem('fundal_height', AntenatalCategory.exam),
    AntenatalItem('urine_protein', AntenatalCategory.lab),
    AntenatalItem('us_anomaly', AntenatalCategory.imaging),
  ]),

  // III посещение — 26–28 недель. Fetal heartbeat, the glucose-tolerance test,
  // and anti-D for rhesus-negative mothers.
  AntenatalVisit(number: 3, fromWeek: 26, toWeek: 28, items: [
    AntenatalItem('risk_review', AntenatalCategory.counsel),
    AntenatalItem('bp_pulse', AntenatalCategory.exam),
    AntenatalItem('legs_varicose', AntenatalCategory.exam),
    AntenatalItem('fundal_height', AntenatalCategory.exam),
    AntenatalItem('fetal_heartbeat', AntenatalCategory.exam),
    AntenatalItem('urine_protein', AntenatalCategory.lab),
    AntenatalItem('ogtt', AntenatalCategory.lab, risk: true),
    AntenatalItem('anti_d', AntenatalCategory.prophylaxis, risk: true),
  ]),

  // IV посещение — 30 недель. Maternity leave is issued; repeat serology; the
  // third-trimester growth scan opens now (30+0–32+6).
  AntenatalVisit(number: 4, fromWeek: 30, toWeek: 30, items: [
    AntenatalItem('risk_review', AntenatalCategory.counsel),
    AntenatalItem('therapist', AntenatalCategory.counsel),
    AntenatalItem('weight_recheck', AntenatalCategory.exam, risk: true),
    AntenatalItem('bp_pulse', AntenatalCategory.exam),
    AntenatalItem('legs_varicose', AntenatalCategory.exam),
    AntenatalItem('fundal_height', AntenatalCategory.exam),
    AntenatalItem('fetal_heartbeat', AntenatalCategory.exam),
    AntenatalItem('us_growth', AntenatalCategory.imaging),
    AntenatalItem('cbc', AntenatalCategory.lab),
    AntenatalItem('syphilis', AntenatalCategory.lab),
    AntenatalItem('hiv', AntenatalCategory.lab),
    AntenatalItem('urine_protein', AntenatalCategory.lab),
    AntenatalItem('maternity_leave', AntenatalCategory.prophylaxis),
  ]),

  // V посещение — 34 недель.
  AntenatalVisit(number: 5, fromWeek: 34, toWeek: 34, items: [
    AntenatalItem('risk_review', AntenatalCategory.counsel),
    AntenatalItem('birth_school', AntenatalCategory.counsel),
    AntenatalItem('bp_pulse', AntenatalCategory.exam),
    AntenatalItem('legs_varicose', AntenatalCategory.exam),
    AntenatalItem('fundal_height', AntenatalCategory.exam),
    AntenatalItem('fetal_heartbeat', AntenatalCategory.exam),
    AntenatalItem('urine_protein', AntenatalCategory.lab),
  ]),

  // VI посещение — 36 недель. Presentation is checked; breastfeeding and
  // postpartum contraception are discussed.
  AntenatalVisit(number: 6, fromWeek: 36, toWeek: 36, items: [
    AntenatalItem('risk_review', AntenatalCategory.counsel),
    AntenatalItem('breastfeeding_contraception', AntenatalCategory.counsel),
    AntenatalItem('fetal_position', AntenatalCategory.exam),
    AntenatalItem('bp_pulse', AntenatalCategory.exam),
    AntenatalItem('legs_varicose', AntenatalCategory.exam),
    AntenatalItem('fundal_height', AntenatalCategory.exam),
    AntenatalItem('fetal_heartbeat', AntenatalCategory.exam),
    AntenatalItem('urine_protein', AntenatalCategory.lab),
    AntenatalItem('syphilis', AntenatalCategory.lab),
  ]),

  // VII посещение — 38 недель.
  AntenatalVisit(number: 7, fromWeek: 38, toWeek: 38, items: [
    AntenatalItem('risk_review', AntenatalCategory.counsel),
    AntenatalItem('postterm_talk', AntenatalCategory.counsel),
    AntenatalItem('bp_pulse', AntenatalCategory.exam),
    AntenatalItem('legs_varicose', AntenatalCategory.exam),
    AntenatalItem('fetal_position', AntenatalCategory.exam),
    AntenatalItem('fundal_height', AntenatalCategory.exam),
    AntenatalItem('fetal_heartbeat', AntenatalCategory.exam),
    AntenatalItem('urine_protein', AntenatalCategory.lab),
  ]),

  // VIII посещение — до 40 недель + 6 дней. The post-term conversation.
  AntenatalVisit(number: 8, fromWeek: 40, toWeek: 40, items: [
    AntenatalItem('risk_review', AntenatalCategory.counsel),
    AntenatalItem('hospital_41w', AntenatalCategory.counsel),
    AntenatalItem('bp_pulse', AntenatalCategory.exam),
    AntenatalItem('legs_varicose', AntenatalCategory.exam),
    AntenatalItem('fetal_position', AntenatalCategory.exam),
    AntenatalItem('fundal_height', AntenatalCategory.exam),
    AntenatalItem('fetal_heartbeat', AntenatalCategory.exam),
    AntenatalItem('urine_protein', AntenatalCategory.lab),
  ]),
];

/// A time-critical screening window that the protocol pins to exact weeks and
/// that CLOSES — the three prenatal ultrasounds, the glucose-tolerance test,
/// anti-D. Held separately from the visits so the screen can warn "this window
/// is open now / closes in N weeks", which is the whole point: a missed window
/// is a missed screening, not a rescheduled one.
class AntenatalWindow {
  /// Stable id, and the l10n stem `an_win_<id>`.
  final String id;

  /// The open window in completed weeks, inclusive.
  final int fromWeek;
  final int toWeek;

  /// True when the window applies only to a risk group (OGTT, anti-D).
  final bool risk;

  const AntenatalWindow({
    required this.id,
    required this.fromWeek,
    required this.toWeek,
    this.risk = false,
  });

  bool isOpenAt(int week) => week >= fromWeek && week <= toWeek;
}

/// The dated screening windows, in gestational order. Weeks are floored to
/// completed weeks: 11+0–13+6 → 11..13, 19+0–21+0 → 19..21, 30+0–32+6 → 30..32.
const List<AntenatalWindow> antenatalWindows = [
  AntenatalWindow(id: 'us_dating', fromWeek: 11, toWeek: 13),
  AntenatalWindow(id: 'serum_markers', fromWeek: 11, toWeek: 13),
  AntenatalWindow(id: 'us_anomaly', fromWeek: 19, toWeek: 21),
  AntenatalWindow(id: 'ogtt', fromWeek: 24, toWeek: 28, risk: true),
  AntenatalWindow(id: 'anti_d', fromWeek: 28, toWeek: 30, risk: true),
  AntenatalWindow(id: 'us_growth', fromWeek: 30, toWeek: 32),
];

/// The visit whose window contains [week], or null between visits.
AntenatalVisit? visitAtWeek(int week) {
  for (final v in antenatalVisits) {
    if (v.coversWeek(week)) return v;
  }
  return null;
}

/// The next visit strictly after [week] — what to prepare for when none is due
/// right now. Null once the last visit's window has passed.
AntenatalVisit? nextVisitAfter(int week) {
  for (final v in antenatalVisits) {
    if (v.fromWeek > week) return v;
  }
  return null;
}

/// The visit that is either due now (its window contains [week]) or, failing
/// that, the next one coming up. Null only once week is past the final window —
/// i.e. term has arrived. This is the single "what now" the screen leads with.
AntenatalVisit? currentOrNextVisit(int week) => visitAtWeek(week) ?? nextVisitAfter(week);

/// The screening windows open at [week], in gestational order.
List<AntenatalWindow> windowsOpenAt(int week) =>
    [for (final w in antenatalWindows) if (w.isOpenAt(week)) w];

/// How many visits fall on or before [week] — a woman's progress through the
/// eight-visit plan, for a "visit 3 of 8" style summary.
int visitsCompletedBy(int week) =>
    antenatalVisits.where((v) => v.toWeek <= week).length;

/// The calendar date a visit's window OPENS, given the estimated due date.
///
/// The due date is 40 completed weeks of gestation, so the start of completed
/// week W is (40 − W) weeks before it. We target the opening of the window
/// ([AntenatalVisit.fromWeek]) — the earliest the visit is due — as the default
/// date to book; the mother can always move it. Time-of-day is left to the
/// caller (the booking sets a sensible clinic hour).
///
/// This is what makes the protocol actionable: it turns "visit 3 is due at
/// 26–28 weeks" into a real date she can put in her own appointments.
DateTime visitOpensOn(AntenatalVisit visit, DateTime dueDate) =>
    DateTime(dueDate.year, dueDate.month, dueDate.day)
        .subtract(Duration(days: (40 - visit.fromWeek) * 7));
