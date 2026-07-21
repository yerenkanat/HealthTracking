/// Whether a triage emergency is acted on now, or needs a second reading first.
///
/// PURE Dart, verified by `dart run tool/verify_emergency_confirmation.dart`.
///
/// WHY THIS EXISTS
///
/// assessTelemetry judges one frame at a time — it is the shared, stateless rule
/// module, and it must stay that way. But a single frame is a thin basis for
/// taking over a pregnant woman's screen with "seek emergency care now":
///
///   * a wrist PPG blood-pressure estimate carries roughly ±10-15 mmHg of error,
///     so a woman whose true systolic is 130 crosses the 140 line regularly;
///   * blood pressure genuinely spikes for a minute at a time with movement,
///     stress or position, without meaning anything;
///   * the band samples continuously, so every one of those moments is seen.
///
/// ACOG diagnoses gestational hypertension on two elevated readings at least
/// four hours apart, for exactly this reason. Four hours is far too long to sit
/// on a warning, but the principle — do not act on one noisy number — holds.
/// Escalating on every crossing produces alarm fatigue, and alarm fatigue is how
/// the real emergency gets ignored.
///
/// So: the first crossing asks her to measure again. A crossing that persists
/// escalates. A one-off expires quietly.
///
/// WHAT IS NOT GATED
///
/// A reading she typed in herself came off a real cuff, deliberately, and is not
/// an estimate. Those escalate immediately — making her confirm a measurement
/// she already took by hand would be both insulting and dangerous.
library;

/// Where a reading came from. The distinction is the whole point: one is an
/// estimate from a sensor on her wrist, the other is a measurement she took.
enum ReadingSource { sensor, manual }

/// What to do about an emergency-severity finding.
enum EscalationAction {
  /// Nothing to show — no finding, or one already asked about.
  none,

  /// First crossing from a sensor. Ask her to measure again rather than
  /// declaring an emergency on one estimate.
  askToRepeat,

  /// Act on it: take over the screen.
  escalate,
}

class EscalationDecision {
  final EscalationAction action;

  /// The triage code this is about, when there is one.
  final String? code;

  const EscalationDecision(this.action, {this.code});

  static const nothing = EscalationDecision(EscalationAction.none);

  bool get shouldEscalate => action == EscalationAction.escalate;
  bool get shouldAskToRepeat => action == EscalationAction.askToRepeat;
}

/// Which measurement a triage code is about.
///
/// Grouped rather than compared code-for-code so that a reading which crosses
/// the ordinary threshold and then the severe one counts as the same condition
/// persisting — which is precisely the case that should escalate fastest, not
/// the one that starts the count over.
String? emergencyFamily(String? code) {
  if (code == null) return null;
  if (code.startsWith('PREECLAMPSIA_BP')) return 'bp';
  if (code.endsWith('FEVER')) return 'fever';
  if (code.startsWith('HYPOXIA')) return 'spo2';
  if (code.startsWith('TACHY') || code.startsWith('BRADY')) return 'hr';
  return code; // anything unrecognised stands alone, which is the safe default
}

class EmergencyConfirmation {
  /// How long a crossing stays pending. Past this it is treated as a one-off.
  final Duration window;

  /// The least time that must separate the two crossings.
  ///
  /// Without this the gate would be useless: the band emits frames seconds
  /// apart, so a single artifact would confirm itself immediately. Two minutes
  /// of a condition persisting is worth acting on; two seconds is not.
  final Duration minSpacing;

  /// When each family's pending crossing was first seen.
  final Map<String, DateTime> _pendingSince = {};

  EmergencyConfirmation({
    this.window = const Duration(minutes: 30),
    this.minSpacing = const Duration(minutes: 2),
  });

  /// Decide what to do about one reading.
  ///
  /// [isEmergency] is triage's own verdict; this only decides whether to act on
  /// it yet. Anything below emergency severity never reaches here.
  EscalationDecision consider({
    required String? code,
    required bool isEmergency,
    required ReadingSource source,
    required DateTime at,
  }) {
    if (!isEmergency) return EscalationDecision.nothing;

    // A measurement she took by hand is not an estimate. Act on it.
    if (source == ReadingSource.manual) {
      return EscalationDecision(EscalationAction.escalate, code: code);
    }

    final family = emergencyFamily(code) ?? 'unknown';
    _dropExpired(at);

    final since = _pendingSince[family];
    if (since == null) {
      _pendingSince[family] = at;
      return EscalationDecision(EscalationAction.askToRepeat, code: code);
    }

    if (at.difference(since) >= minSpacing) {
      // It has persisted. Clear the pending state so the next episode starts
      // its own count rather than escalating instantly off this one.
      _pendingSince.remove(family);
      return EscalationDecision(EscalationAction.escalate, code: code);
    }

    // Still inside the spacing window: already asked, do not nag. The original
    // timestamp is kept deliberately, so spacing is measured from the first
    // crossing rather than being pushed forward by every frame that follows.
    return EscalationDecision.nothing;
  }

  /// Forget a pending crossing older than [window].
  ///
  /// Note what this does NOT do: a single normal reading does not clear it.
  /// Sensor noise cuts both ways, and letting one low estimate cancel a real
  /// rise would put the gate's error in the dangerous direction.
  void _dropExpired(DateTime now) {
    _pendingSince.removeWhere((_, since) => now.difference(since) > window);
  }

  /// Whether a family is waiting on a confirming reading — for a UI that wants
  /// to show "measure again" until it resolves.
  bool isPending(String family) => _pendingSince.containsKey(family);

  /// The measurement waiting on a repeat as of [now], or null.
  ///
  /// The single source of truth for the "take another reading" prompt. The
  /// controller used to keep its own copy of this, set when a crossing was
  /// first seen and cleared only by an escalation or an account reset —
  /// so a lone artifact left the prompt on a pregnant woman's dashboard
  /// permanently, with nothing wrong with her and no way to dismiss it.
  /// Expiry lived here and the prompt lived there.
  ///
  /// Takes [now] because expiry is a function of time, not of anything
  /// happening: the crossing lapses whether or not another reading arrives.
  /// The oldest pending family wins when several are waiting — it is the one
  /// closest to resolving either way.
  String? pendingFamilyAt(DateTime now) {
    _dropExpired(now);
    if (_pendingSince.isEmpty) return null;
    var oldest = _pendingSince.entries.first;
    for (final e in _pendingSince.entries) {
      if (e.value.isBefore(oldest.value)) oldest = e;
    }
    return oldest.key;
  }

  /// Drop all pending state, e.g. on sign-out or a band change.
  void clear() => _pendingSince.clear();
}
