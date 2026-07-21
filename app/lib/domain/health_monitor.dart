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

class HealthMonitor {
  final String deviceId;
  final EnqueueTelemetry enqueue;
  final EmergencyHandler onEmergency;
  final Clock _now;

  BandTelemetry? _latest;
  TriageResult? _latestTriage;
  StreamSubscription<(BandTelemetry, TriageResult)>? _sub;

  HealthMonitor({
    required this.deviceId,
    required this.enqueue,
    required this.onEmergency,
    Clock? now,
  }) : _now = now ?? DateTime.now;

  BandTelemetry? get latest => _latest;
  TriageResult? get latestTriage => _latestTriage;

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
