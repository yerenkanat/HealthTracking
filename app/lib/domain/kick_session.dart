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
