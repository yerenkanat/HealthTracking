/// HealthMonitor — the app's orchestration brain for the pregnancy module.
/// Wires the BLE telemetry stream to three consequences:
///   1. enqueue the reading for sync (URGENT if it's an emergency → bypasses batch);
///   2. remember the latest reading (so /ai/chat can attach it);
///   3. on emergency, invoke `onEmergency` → the app pushes the Emergency Rescue screen.
///
/// Pure Dart. The batcher/enqueue is injected as a callback (not the concrete
/// TelemetryBatcher) so this is unit-testable without timers or disk.
library;

import 'dart:async';
import '../core/triage.dart';

typedef EnqueueTelemetry = void Function(Map<String, dynamic> telemetry, {required bool urgent});
typedef EmergencyHandler = void Function(TriageResult triage, BandTelemetry telemetry);
typedef Clock = DateTime Function();

/// How long a reading still describes how she is *now*.
///
/// [latest] is attached to every assistant message, and the server treats a
/// critical one as grounds to skip the model and open the Emergency Rescue
/// screen — see AIGuardrailProcessor step 1, which overrides everything.
///
/// Nothing expired it. A reading of 175/118 entered on Monday — acted on,
/// treated, resolved — was still attached on Friday, so an unrelated question
/// about a mild headache was answered by throwing the emergency screen at her
/// again. Repeated false alarms are how an emergency screen stops being read.
///
/// Six hours covers "I measured this morning, I'm asking at lunch" and little
/// more. Past that the guardrail still has her words — the symptom and
/// combination rules run on the message itself — it just no longer has a
/// measurement it can pretend is current.
const latestTelemetryMaxAge = Duration(hours: 6);

class HealthMonitor {
  final String deviceId;
  final EnqueueTelemetry enqueue;
  final EmergencyHandler onEmergency;
  final Clock _now;

  BandTelemetry? _latest;
  TriageResult? _latestTriage;
  DateTime? _latestAt;
  StreamSubscription<(BandTelemetry, TriageResult)>? _sub;

  HealthMonitor({
    required this.deviceId,
    required this.enqueue,
    required this.onEmergency,
    Clock? now,
  }) : _now = now ?? DateTime.now;

  /// The last reading, if it is still recent enough to describe her now.
  BandTelemetry? get latest => _stale ? null : _latest;
  TriageResult? get latestTriage => _stale ? null : _latestTriage;

  /// When the remembered reading was taken, regardless of its age. The vitals
  /// card shows the value with its timestamp, which stays honest as it ages —
  /// only the assistant's "this is how she is right now" claim expires.
  DateTime? get latestAt => _latestAt;

  bool get _stale {
    final at = _latestAt;
    if (at == null) return true;
    return _now().difference(at) > latestTelemetryMaxAge;
  }

  /// Subscribe to BLEDeviceManager.onTelemetry.
  ///
  /// Replaces any existing subscription rather than adding one. Binding twice
  /// — after a re-pair, say — used to leave the first listener live, so every
  /// reading was handled twice: enqueued twice, and an emergency raised twice.
  void bind(Stream<(BandTelemetry, TriageResult)> telemetryStream) {
    unawaited(_sub?.cancel());
    _sub = telemetryStream.listen((rec) => handle(rec.$1, rec.$2));
  }

  /// Core decision — exposed directly for testing.
  void handle(BandTelemetry t, TriageResult triage) {
    record(t, triage);
    final urgent = triage.forceEmergencyScreen;
    enqueue(_wire(t), urgent: urgent);
    if (urgent) onEmergency(triage, t);
  }

  /// Remember a reading WITHOUT enqueuing or escalating it.
  ///
  /// For readings that reached the app by another route and have already been
  /// dealt with — a hand-entered cuff reading, which the controller queues and
  /// triages itself. Calling [handle] for those would send them twice.
  ///
  /// This matters because [latest] is what AiChatService attaches to a chat
  /// message, and the server uses it to bypass the LLM and escalate when the
  /// reading is critical. Only band readings ever reached here, and the band
  /// is not wired yet — so a mother could enter 175/118, ask the assistant
  /// about her headache, and the request carried no reading at all. The
  /// guardrail's most important input was always null.
  void record(BandTelemetry t, TriageResult triage) {
    _latest = t;
    _latestTriage = triage;
    _latestAt = _now();
  }

  Map<String, dynamic> _wire(BandTelemetry t) => {
        'deviceId': deviceId,
        'recordedAt': _now().toUtc().toIso8601String(),
        ...t.toJson(),
      };

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
