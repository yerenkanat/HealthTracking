/// Entry point + composition root for the Flutter app.
///
/// Builds the AppController and (once the user has paired a band / configured a
/// child) wires the device + backend into it. The wiring is factored into
/// `bootstrapRuntime` so the widget tree can start immediately and degrade
/// gracefully when hardware/permissions/network aren't ready yet.
library;

import 'dart:async';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'data/prefs_app_store.dart';
import 'domain/ai_chat_service.dart';
import 'domain/chat_controller.dart';
import 'domain/health_monitor.dart';
import 'data/api_client.dart';
import 'data/http_transport.dart';
import 'l10n/l10n.dart';
import 'net/telemetry_batcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // NOTE: initialize Firebase (auth + messaging) here before runApp in production.

  // Restore a saved session (language, profile, child, zones) BEFORE first paint,
  // so a returning user skips straight past onboarding.
  final controller = AppController(persistStore: PrefsAppStore());
  await controller.restore();
  runApp(FcsApp(controller: controller));

  // Kick off device + backend wiring without blocking first paint.
  unawaited(bootstrapRuntime(controller));
}

/// Connects the verified spine to live sources. Kept out of the widget tree so
/// UI is testable and the app still renders if any of this is unavailable.
Future<void> bootstrapRuntime(AppController controller) async {
  try {
    final api = ApiClient(HttpApiTransport(
      baseUrl: Uri.parse(
          const String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080')),
      getToken: () async => null, // TODO: Firebase Auth ID token
    ));

    // Offline-first batcher → flushes batches to /ingest/batch.
    final batcher = TelemetryBatcher(BatcherConfig(
      maxBatch: 25,
      maxDelay: const Duration(seconds: 30),
      flush: (items) => api.ingestBatch(items.map((i) => i.toJson()).toList()),
      persist: (_) async {}, // TODO: MMKV disk mirror
      restore: () async => [],
    ));
    await batcher.init();

    // HealthMonitor: on-device triage → batcher (urgent bypass on emergencies).
    // onEmergency forwards to the controller (note: HealthMonitor's signature is
    // (triage, telemetry); AppController.onTelemetry is (telemetry, triage)).
    final monitor = HealthMonitor(
      deviceId: const String.fromEnvironment('BAND_ID', defaultValue: 'band-unpaired'),
      enqueue: (t, {required urgent}) => batcher.enqueueTelemetry(t, urgent: urgent),
      onEmergency: (triage, t) => controller.onTelemetry(t, triage),
    );

    controller.attachRuntime(monitor: monitor, batcher: batcher, api: api);

    // Assistant: guardrailed chat. Emergencies escalate into the app-wide
    // Emergency Rescue screen via the controller.
    final chatService = AiChatService(
      api: api,
      userId: const String.fromEnvironment('USER_ID', defaultValue: 'me'),
      locale: controller.locale.name,
      monitor: monitor,
      onEmergency: (e) => controller.onChatEmergency(e.message, e.callButtons),
    );
    controller.attachChat(ChatController(
      service: chatService,
      networkErrorText: () => L10n(controller.locale).t('chat_error'),
      emergencyNoteText: () => L10n(controller.locale).t('chat_emergency_note'),
    ));

    // TODO(once paired): construct BleDeviceManager(config) and:
    //   ble.onTelemetry.listen((rec) {
    //     controller.onTelemetry(rec.$1, rec.$2);   // dashboard + emergency
    //     monitor.handle(rec.$1, rec.$2);            // sync + batching
    //   });
    //   ble.onBeacon.listen((r) => controller.onChildLocation(resolveFix(r)));
    //   await ble.start();
    //
    // TODO(after sign-in): controller.configureChild(name, fences) from the backend.
  } catch (_) {
    // Degrade gracefully — the UI already rendered; retry wiring on next launch.
  }
}
