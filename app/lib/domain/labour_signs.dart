/// Signs that labour may be starting, and when to go in.
///
/// PURE Dart → verified by tool/verify_labour_signs.dart.
///
/// The companion to the contraction timer: the timer answers "is this the
/// 5-1-1 pattern?", and this answers the questions around it — what tells you
/// labour is beginning, and which signs mean go to the hospital or call now,
/// not wait. Reference, not instruction: every "go in" item points outward to
/// the clinic, and when in doubt the advice is to call.
library;

/// Signs that labour may be starting — informational, not alarming. Each is an
/// l10n stem `lab_sign_<id>`.
const List<String> labourSigns = [
  'contractions', // regular, strengthening, closer together
  'show', // the mucus plug comes away
  'backache', // low back ache / period-like cramps
  'waters', // waters break, a trickle or a gush
];

/// The signs that mean head to the hospital or call the clinic now — never
/// softened. Each is an l10n stem `lab_go_<id>`.
const List<String> labourGoIn = [
  'waters_broke', // waters broken (urgent if green/brown/bloody)
  'five_one_one', // the 5-1-1 contraction pattern
  'bleeding', // any vaginal bleeding
  'reduced_movements', // the baby moving much less
  'preterm', // any signs of labour before 37 weeks
  'unsure', // if unsure at all — call, they will guide you
];

/// The week before which labour signs are "preterm" and always warrant a call.
const pretermBeforeWeek = 37;

/// The 5-1-1 rule, as three numbers, so the copy and the contraction timer agree
/// on the same figures.
const fiveOneOneEveryMin = 5;
const fiveOneOneLastingMin = 1;
const fiveOneOneForHours = 1;
