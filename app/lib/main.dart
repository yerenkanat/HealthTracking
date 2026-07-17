/// Entry point + composition root for the Flutter app.
///
/// Builds the AppController and (once the user has paired a band / configured a
/// child) wires the device + backend into it. The wiring is factored into
/// `bootstrapRuntime` so the widget tree can start immediately and degrade
/// gracefully when hardware/permissions/network aren't ready yet.
library;

import 'dart:async';
import 'package:flutter/material.dart' hide Flow;

import 'app/app.dart';
import 'app/app_controller.dart';
import 'core/geofence.dart';
import 'data/notification_service.dart';
import 'data/prefs_app_store.dart';
import 'domain/geofence_alerts.dart';
import 'domain/cycle_log.dart';
import 'domain/health_series.dart';
import 'domain/sleep.dart';
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
  if (const bool.fromEnvironment('DEMO')) _seedDemo(controller);
  runApp(FcsApp(controller: controller));

  // Kick off device + backend wiring without blocking first paint.
  unawaited(bootstrapRuntime(controller));
}

/// Demo seed (only with --dart-define=DEMO=true): realistic band samples + a
/// child with zones, so the redesigned UI can be shown without a physical band.
void _seedDemo(AppController c) {
  final now = DateTime.now();
  final hr = [72, 74, 73, 76, 78, 75, 79, 81, 80, 83, 85, 84];
  final samples = <HealthSample>[
    for (var i = 0; i < 12; i++)
      HealthSample(
        at: now.subtract(Duration(minutes: (12 - i) * 5)),
        heartRate: hr[i].toDouble(),
        spo2: (97 + (i % 2)).toDouble(),
        systolic: (116 + i * 2).toDouble(), // rises to 138 → "watch" advisory
        diastolic: (74 + i ~/ 3).toDouble(),
        coreTemp: 36.5 + (i % 3) * 0.1,
        duringSleep: i < 4,
      ),
  ];
  c.debugSeed(samples);

  // A week of nightly sleep summaries (deep / rem / light / awake, minutes).
  final today = DateTime(now.year, now.month, now.day);
  const nightsData = [
    [95, 105, 280, 25], // last night — solid
    [70, 90, 250, 35],
    [55, 80, 300, 40],
    [90, 110, 270, 20],
    [40, 70, 230, 55], // short night
    [85, 95, 285, 30],
    [100, 115, 260, 22],
  ];
  c.debugSeedSleep([
    for (var i = 0; i < nightsData.length; i++)
      SleepSummary(
        night: today.subtract(Duration(days: i)),
        deepMin: nightsData[i][0],
        remMin: nightsData[i][1],
        lightMin: nightsData[i][2],
        awakeMin: nightsData[i][3],
      ),
  ]);

  c.configureChild(
    name: 'Sultan',
    dateOfBirth: DateTime(now.year - 8, now.month, now.day), // ~8 yrs → school-age tips
    fences: [
      Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100),
      Geofence.circle('school', 'School', const Coordinates(43.25, 76.95), 120),
    ],
  );
  // Two past menstrual periods (~28-day cycle, 5 days each) so the cycle tracker
  // shows real predictions out of the box: last period ended a few days ago →
  // ~cycle day 7, next period in ~3 weeks.
  for (final start in [today.subtract(const Duration(days: 6)), today.subtract(const Duration(days: 34))]) {
    for (var i = 0; i < 5; i++) {
      final d = start.add(Duration(days: i));
      c.setDayLog(DayLog(date: dateKey(d), flow: i < 2 ? Flow.medium : Flow.light));
    }
  }

  // A short movement history → generates zone enter/exit alerts for the feed:
  // at Home → on the move → arrives at School (where the map leaves them).
  c.onChildLocation(const Coordinates(43.238949, 76.889709)); // Home → entered Home
  c.onChildLocation(const Coordinates(43.245, 76.92)); // between → left Home
  c.onChildLocation(const Coordinates(43.25, 76.95)); // School → entered School

  c.debugMarkOnboarded(); // demo skips onboarding → lands straight in the app
}

/// Connects the verified spine to live sources. Kept out of the widget tree so
/// UI is testable and the app still renders if any of this is unavailable.
Future<void> bootstrapRuntime(AppController controller) async {
  // On-device notifications for child zone alerts. The controller only emits to
  // newAlerts while the user's notifications preference is on, so this is the sole
  // gate we need here. Best-effort — the app works fine without it.
  try {
    final notifications = LocalNotificationService();
    await notifications.init();
    await notifications.requestPermission();
    controller.newAlerts.listen((alert) {
      final l = L10n(controller.locale);
      final title = l.t(alert.kind == AlertKind.entered ? 'alert_entered' : 'alert_left', {'zone': alert.zoneName});
      notifications.show(title: title, body: alert.childName);
    });

    // Appointment reminders: schedule/cancel OS notifications as they change,
    // then reconcile once so future reminders survive a reinstall / reboot.
    controller.reminderCommands.listen((cmd) {
      if (cmd.at == null) {
        notifications.cancel(cmd.id);
      } else {
        notifications.scheduleAt(id: cmd.id, title: cmd.title!, body: cmd.body!, at: cmd.at!);
      }
    });
    controller.rescheduleReminders();

    // DEMO only: 3s after launch the child moves School → Home, firing real
    // "left School" + "entered Home" notifications so the feature is visible.
    if (const bool.fromEnvironment('DEMO')) {
      Future.delayed(const Duration(seconds: 3),
          () => controller.onChildLocation(const Coordinates(43.238949, 76.889709)));
    }
  } catch (_) {/* notifications are best-effort */}

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
