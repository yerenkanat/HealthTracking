/// Timed fetal-movement session — a pure model for the "count the kicks" tool.
/// The clock starts on the FIRST recorded movement (a common way expectant
/// parents time a session), and the model just counts taps + measures elapsed
/// time. NON-medical: no thresholds, targets, or guidance live here. PURE Dart →
/// unit-testable via verify_kicks.dart.
library;

class KickSession {
  final int count;
  final DateTime? startedAt; // null until the first movement is recorded

  const KickSession({this.count = 0, this.startedAt});

  bool get started => startedAt != null;

  /// Record one movement. Stamps [startedAt] on the very first tap so the clock
  /// measures from the first kick, not from when the screen opened.
  KickSession tap(DateTime now) => KickSession(
        count: count + 1,
        startedAt: startedAt ?? now,
      );

  /// Undo the last movement. Once the count returns to zero the clock resets
  /// (an accidental first tap shouldn't leave a session "running").
  KickSession undo() {
    if (count <= 0) return const KickSession();
    final next = count - 1;
    return KickSession(count: next, startedAt: next == 0 ? null : startedAt);
  }

  /// Elapsed time since the session started (zero before the first tap).
  Duration elapsed(DateTime now) =>
      startedAt == null ? Duration.zero : now.difference(startedAt!);
}

/// A completed session, kept in history: how many movements, how long it ran,
/// and when it ended. Pure + JSON-serializable for persistence.
class KickSessionRecord {
  final DateTime endedAt;
  final int count;
  final int durationSec;

  const KickSessionRecord({required this.endedAt, required this.count, required this.durationSec});

  Duration get duration => Duration(seconds: durationSec);

  Map<String, dynamic> toJson() => {
        'endedAt': endedAt.toIso8601String(),
        'count': count,
        'durationSec': durationSec,
      };

  factory KickSessionRecord.fromJson(Map<String, dynamic> j) => KickSessionRecord(
        endedAt: DateTime.parse(j['endedAt'] as String),
        count: (j['count'] as num).toInt(),
        durationSec: (j['durationSec'] as num).toInt(),
      );
}

/// A per-session movement goal — a neutral personal target (not medical advice),
/// with a progress fraction for the ring.
const int defaultKickGoal = 10;

/// Progress toward [goal], clamped 0..1.
double kickGoalFraction(int count, int goal) {
  if (goal <= 0 || count <= 0) return 0;
  final f = count / goal;
  return f > 1 ? 1 : f;
}

/// Whether the session reached its goal.
bool kickGoalReached(int count, int goal) => goal > 0 && count >= goal;

/// The window taught with the "count to ten" method: ten movements within about
/// two hours. Referenced here the same way the labour timer references 5-1-1 —
/// as a widely-taught pattern to describe against, never as a diagnosis.
const Duration kickReferenceWindow = Duration(hours: 2);

/// Whether the goal was reached WITHIN the reference window.
///
/// The goal used to be judged on count alone, so ten movements felt over three
/// hours produced the same "Goal reached 🎉" as ten in twenty minutes. That is a
/// celebration at the exact moment the count-to-ten method exists to notice:
/// taking much longer than usual to feel ten movements is the thing a mother is
/// asked to report, and the app was congratulating her for it.
///
/// This does not diagnose anything and does not tell her what to do — it only
/// decides whether the moment deserves confetti, and lets the UI show a calm,
/// provider-deferring note instead when it does not.
bool kickGoalReachedPromptly(int count, Duration elapsed, {int goal = defaultKickGoal}) =>
    kickGoalReached(count, goal) && elapsed <= kickReferenceWindow;

/// Aggregate stats over recorded kick sessions — for the history header.
class KickHistorySummary {
  final int sessions;
  final double avgCount; // average movements per session
  final Duration avgDuration; // average session length
  final int goalReached; // sessions that met the goal
  const KickHistorySummary(this.sessions, this.avgCount, this.avgDuration, this.goalReached);
}

/// Summarize [records] against [goal]. Empty history → all zero.
KickHistorySummary kickHistorySummary(List<KickSessionRecord> records, {int goal = defaultKickGoal}) {
  if (records.isEmpty) return const KickHistorySummary(0, 0, Duration.zero, 0);
  var countSum = 0, durSum = 0, reached = 0;
  for (final r in records) {
    countSum += r.count;
    durSum += r.durationSec;
    if (kickGoalReached(r.count, goal)) reached++;
  }
  return KickHistorySummary(
    records.length,
    countSum / records.length,
    Duration(seconds: (durSum / records.length).round()),
    reached,
  );
}

/// Running-clock label: "M:SS", or "H:MM:SS" once past an hour. Negative or
/// zero durations render as "0:00".
String formatElapsed(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final h = total.inHours;
  final m = total.inMinutes % 60;
  final s = total.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
