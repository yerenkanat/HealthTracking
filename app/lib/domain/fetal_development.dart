/// What the baby is developing, week by week.
///
/// PURE Dart → verified by tool/verify_fetal_development.dart.
///
/// WHAT THIS IS
///
/// The one line Flo leads its weekly card with: "this week, baby is…". The app
/// already shows the SIZE and the trimester milestones, but not the small
/// wonders in between — the heartbeat at week five, hearing your voice at
/// twenty, opening the eyes at twenty-six. This is that thread, curated one
/// highlight at a time from week five to term.
///
/// WHAT IT IS NOT
///
/// Not a scan and not a measurement of a particular baby. These are the typical
/// developments of an average pregnancy, and like the size comparison they are
/// approximate and illustrative — a companion's "look what's happening", not a
/// clinical record.
///
/// Each entry carries a CODE the UI localizes (`fet_<id>`). Weeks are completed
/// weeks. Curated at roughly one highlight per week or two, so `fetalHighlightFor`
/// can snap any week back to the most recent one — the same trick baby_size uses.
library;

typedef FetalHighlight = ({int week, String id});

/// The developments, in week order. One stem each: `fet_<id>`.
const List<FetalHighlight> fetalHighlights = [
  (week: 5, id: 'heartbeat'), // the heart begins to beat
  (week: 6, id: 'neural'), // brain and spinal cord take shape
  (week: 7, id: 'limb_buds'), // tiny arm and leg buds
  (week: 8, id: 'fingers'), // fingers and toes begin to form
  (week: 9, id: 'organs'), // the essential organs are in place
  (week: 10, id: 'nails'), // joints bend, nails start
  (week: 11, id: 'bones'), // bones begin to harden
  (week: 12, id: 'reflexes'), // reflexes; can make sucking movements
  (week: 14, id: 'expressions'), // can squint and frown
  (week: 16, id: 'fist'), // can make a fist
  (week: 18, id: 'hearing'), // ears in position; may pick up sounds
  (week: 20, id: 'voice'), // can hear your voice
  (week: 22, id: 'touch'), // sense of touch and taste developing
  (week: 24, id: 'responds'), // responds to sound with movement
  (week: 26, id: 'eyes_open'), // the eyes begin to open
  (week: 28, id: 'dreams'), // brain very active; phases of REM sleep
  (week: 30, id: 'light'), // can tell light from dark
  (week: 32, id: 'breathing'), // practises breathing movements
  (week: 34, id: 'lungs'), // lungs nearly ready
  (week: 36, id: 'head_down'), // often settling head-down
  (week: 38, id: 'term'), // considered full term soon
  (week: 40, id: 'ready'), // ready to meet you
];

/// The highlight for [week] — the most recent entry whose week ≤ [week]. Null
/// before the first entry (very early weeks have no meaningful highlight yet).
FetalHighlight? fetalHighlightFor(int week) {
  if (week < fetalHighlights.first.week) return null;
  var current = fetalHighlights.first;
  for (final h in fetalHighlights) {
    if (h.week > week) break;
    current = h;
  }
  return current;
}
