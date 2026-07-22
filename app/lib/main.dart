/// Entry point + composition root for the Flutter app.
///
/// Builds the AppController and (once the user has paired a band / configured a
/// child) wires the device + backend into it. The wiring is factored into
/// `bootstrapRuntime` so the widget tree can start immediately and degrade
/// gracefully when hardware/permissions/network aren't ready yet.
library;

import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart' hide Flow;

import 'app/app.dart';
import 'app/app_controller.dart';
import 'core/geofence.dart';
import 'package:path_provider/path_provider.dart';

import 'data/notification_service.dart';
import 'data/content_repository.dart';
import 'data/photo_paths.dart';
import 'data/content_store.dart';
import 'data/prefs_app_store.dart';
import 'domain/geofence_alerts.dart';
import 'domain/notification_ids.dart';
import 'domain/error_log.dart';
import 'ui/widgets/error_fallback.dart';
import 'domain/cycle_log.dart';
import 'domain/health_series.dart';
import 'domain/sleep.dart';
import 'domain/wearable_metrics.dart';
import 'ble/starmax/starmax_ble_transport.dart';
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

  // Where photos live on THIS install. Resolved once, before first paint,
  // because the avatar needs it during build and iOS renames the application
  // container on every update — a photo saved as an absolute path stopped
  // resolving and quietly disappeared. See data/photo_paths.dart.
  try {
    photosDocsPath = (await getApplicationDocumentsDirectory()).path;
  } catch (_) {
    // No documents directory is not a reason to fail to start; avatars fall
    // back to initials, exactly as they do for someone who added no photo.
  }

  // Restore a saved session (language, profile, child, zones) BEFORE first paint,
  // so a returning user skips straight past onboarding.
  final controller = AppController(persistStore: PrefsAppStore());
  _installErrorHandling(controller.errorLog);
  await controller.restore();
  if (const bool.fromEnvironment('DEMO')) _seedDemo(controller);

  // Content from whatever is available WITHOUT the network — the cached
  // response, the bundled asset, or the seeded catalogue. First paint must not
  // wait on a request, so the API refresh happens after runApp and swaps in
  // through the store.
  //
  // This DOES block first paint on a local parse, which looks like something
  // to fix until it is measured: the bundled catalogue is 154 KB and 364
  // items, and decoding plus building it takes 3.3 ms on a desktop — call it
  // 15-35 ms on a slow phone, against Flutter's own startup of several hundred.
  // Deferring it would buy nothing measurable and cost a visible flash of
  // empty content on the home screen. Measured rather than assumed, so the
  // next person does not refactor it on instinct.
  final cache = PrefsContentCache();
  final loaded = await loadCatalogFast(cache: cache);
  if (loaded.fallbackReason != null) {
    debugPrint('content: loaded from ${loaded.source.name} — ${loaded.fallbackReason}');
  }
  final contentStore = ContentStore(loaded.catalog, source: loaded.source);

  runApp(FcsApp(controller: controller, content: contentStore));

  // Kick off device + backend wiring without blocking first paint.
  unawaited(bootstrapRuntime(controller, content: contentStore, contentCache: cache));
}

/// Catch what would otherwise be lost, and put something usable on screen.
///
/// Nothing caught errors before this, and in release that failed twice over,
/// silently: a widget that throws was replaced by a bare grey rectangle with no
/// text and no way out, and an error thrown off the widget tree — a timer, a
/// stream, an unawaited future — vanished entirely. On an app someone opens
/// because they are worried about a reading, neither is acceptable.
///
/// [log] is the controller's, so what is caught here reaches the export the
/// user can send to support. There is no crash reporting service yet; this is
/// the whole of it.
void _installErrorHandling(ErrorLog log) {
  FlutterError.onError = (details) {
    log.add(
      source: AppErrorSource.widget,
      error: details.exception,
      stack: details.stack,
      at: DateTime.now(),
    );
    FlutterError.presentError(details); // keep the console output in debug
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.add(source: AppErrorSource.async, error: error, stack: stack, at: DateTime.now());
    debugPrint('uncaught async error: $error');
    return true; // handled — do not take the app down
  };
  ErrorWidget.builder = (details) => ErrorFallback(
        // The exception text is shown only in debug. In release it is recorded
        // for diagnostics but not put on screen: it is written for us, not for
        // her, and it can quote the reading that caused it.
        details: kDebugMode ? details.exceptionAsString() : null,
      );
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
        night: addDays(today, -i),
        deepMin: nightsData[i][0],
        remMin: nightsData[i][1],
        lightMin: nightsData[i][2],
        awakeMin: nightsData[i][3],
      ),
  ]);

  // Demo: a full watch snapshot so the dashboard's Activity & Wellness panel
  // shows every parameter the health wearable tracks — steps, distance,
  // calories, sleep (deep/light), stress, breathing rate, blood sugar — without
  // a paired device. On a real build this arrives from the watch over BLE
  // (STARMAX_WATCH=true); here it is representative test data.
  c.onWearableMetrics(WearableMetrics(
    at: now,
    steps: 6480,
    kcal: 320,
    meters: 4600, // 4.6 km
    sleepMinutes: 445, // 7h 25m
    deepSleepMinutes: 95,
    lightSleepMinutes: 280,
    stress: 42, // 0–100
    breathRate: 16, // breaths / min
    bloodSugarTenths: 54, // 5.4 mmol/L
    worn: true,
  ));

  // Demo: a due date 140 days out — 280 - 140 = week 20 of pregnancy, so the
  // timeline card has a real stage to show. A mother expecting while already
  // having an older child is an ordinary case, and it exercises the pregnancy
  // half of the timeline (the child here is 8, past the five-year window).
  if (c.dueDate == null) {
    c.updateProfile(c.profile.copyWith(dueDate: addDays(now, 140)));
  }

  c.configureChild(
    name: 'Sultan',
    dateOfBirth: DateTime(now.year - 8, now.month, now.day), // ~8 yrs → school-age tips
    fences: [
      Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100),
      Geofence.circle('school', 'School', const Coordinates(43.25, 76.95), 120),
    ],
  );
  // Demo: a weight entry + target so the weight card shows progress.
  if (c.weights.isEmpty) {
    c.logWeight(addDays(today, -14), 62.0);
    c.logWeight(today, 65.0);
    c.setWeightGoal(72.0);
  }
  // Demo: seed the tracker battery (a short declining series so the history
  // sheet has something to show) so the status chip is populated.
  final demoChild = c.selectedChild;
  if (demoChild != null) {
    for (final pct in [88, 80, 71, 62]) {
      c.setChildBattery(demoChild.id, pct);
    }
  }
  // Demo: an upcoming appointment so the reminders list + calendar dot show data.
  // Guarded so re-running the demo (hot restart) doesn't pile up duplicates.
  if (c.appointments.isEmpty) {
    c.addAppointment('Приём у гинеколога', addDays(today, 5).add(const Duration(hours: 10)));
  }
  // Demo: a week of water so the weekly trend + streak are populated (addWater
  // accumulates, so only seed when there's no water logged yet).
  if (c.waterLog.isEmpty) {
    const demoWater = [6, 8, 5, 8, 9, 8, 8]; // 6 days ago → today (today meets the goal)
    for (var i = 0; i < demoWater.length; i++) {
      c.addWater(addDays(today, -(demoWater.length - 1 - i)), demoWater[i]);
    }
  }
  // Three past menstrual periods (~28-day cycle, 5 days each) so the cycle tracker
  // shows real predictions AND the insights regularity read out of the box: last
  // period ended a few days ago → ~cycle day 7, next period in ~3 weeks.
  for (final start in [
    addDays(today, -6),
    addDays(today, -34),
    addDays(today, -62),
  ]) {
    for (var i = 0; i < 5; i++) {
      final d = addDays(start, i);
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
Future<void> bootstrapRuntime(
  AppController controller, {
  ContentStore? content,
  ContentCache? contentCache,
}) async {
  // On-device notifications for child zone alerts. The controller only emits to
  // newAlerts while the user's notifications preference is on, so this is the sole
  // gate we need here. Best-effort — the app works fine without it.
  try {
    final notifications = LocalNotificationService();
    await notifications.init();
    await notifications.requestPermission();
    controller.newAlerts.listen((alert) {
      final l = L10n(controller.locale);
      final title = switch (alert.kind) {
        AlertKind.entered => l.t('alert_entered', {'zone': alert.zoneName}),
        AlertKind.left => l.t('alert_left', {'zone': alert.zoneName}),
        AlertKind.checkIn => l.t('alert_checkin'),
        AlertKind.sos => l.t('alert_sos'),
        AlertKind.lowBattery => l.t('alert_low_battery', {'pct': alert.zoneName}),
      };
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

    // Daily water reminder: schedule/cancel a repeating notification as the
    // setting changes, then reconcile once on boot.
    const waterReminderId = NotifyIds.water;
    controller.waterReminderCommands.listen((minutes) {
      if (minutes == null) {
        notifications.cancel(waterReminderId);
      } else {
        final l = L10n(controller.locale);
        notifications.scheduleDaily(
          id: waterReminderId,
          title: l.t('water_reminder_title'),
          body: l.t('water_reminder_body'),
          hour: minutes ~/ 60,
          minute: minutes % 60,
        );
      }
    });
    // Daily medication reminder — same repeating-notification shape as water.
    const medReminderId = NotifyIds.medication;
    controller.medReminderCommands.listen((minutes) {
      if (minutes == null) {
        notifications.cancel(medReminderId);
      } else {
        final l = L10n(controller.locale);
        notifications.scheduleDaily(
          id: medReminderId,
          title: l.t('med_reminder_title'),
          body: l.t('med_reminder_body'),
          hour: minutes ~/ 60,
          minute: minutes % 60,
        );
      }
    });
    controller.reconcileWaterReminder();
    controller.reconcileMedReminder();
    controller.reconcileCycleReminders();

    // DEMO only: 3s after launch the child moves School → Home, firing real
    // "left School" + "entered Home" notifications so the feature is visible.
    if (const bool.fromEnvironment('DEMO')) {
      Future.delayed(const Duration(seconds: 3),
          () => controller.onChildLocation(const Coordinates(43.238949, 76.889709)));
      // ...and 7s in, the tracker battery dips low → a low-battery notification.
      final demoChildId = controller.selectedChild?.id;
      if (demoChildId != null) {
        Future.delayed(const Duration(seconds: 7), () => controller.setChildBattery(demoChildId, 8));
      }
    }
  } catch (_) {/* notifications are best-effort */}

  try {
    final api = ApiClient(HttpApiTransport(
      baseUrl: Uri.parse(
          const String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080')),
      getToken: () async => null, // TODO: Firebase Auth ID token
      devUserId: const String.fromEnvironment('DEV_USER_ID'),
    ));

    // Pull whatever the back-office has published. The app already showed the
    // cached or bundled catalogue at first paint, so this only ever upgrades
    // what is on screen — and a failure quietly leaves that in place.
    if (content != null) {
      final fresh = await refreshCatalogFromApi(api: api, cache: contentCache);
      if (fresh != null) content.adopt(fresh, CatalogSource.api);
    }

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
      locale: () => controller.locale.name, // follows the in-app language switch

      monitor: monitor,
      onEmergency: (e) => controller.onChatEmergency(e.message, e.callButtons, code: e.code),
    );
    controller.attachChat(ChatController(
      service: chatService,
      networkErrorText: () => L10n(controller.locale).t('chat_error'),
      emergencyNoteText: () => L10n(controller.locale).t('chat_emergency_note'),
    ));

    // Where the child's position comes from.
    //
    // Nothing supplied it before: onChildLocation had exactly two callers, both
    // in the demo seed, so outside a --dart-define=DEMO build the tracking map
    // said "waiting for location" for ever. Half the product did not work, and
    // it looked like it was merely waiting. ApiClient.lastLocation existed for
    // this and was called from nowhere.
    //
    // Polled rather than pushed because there is no socket yet; the interval is
    // a battery/latency trade, and a geofence alert that arrives a minute late
    // is still worth having.
    unawaited(_pollChildLocation(controller, api));

    // The Starmax / RunmeFit health watch. Opt-in via a build define so a user
    // without one never pays a scan: --dart-define=STARMAX_WATCH=true, and
    // optionally --dart-define=STARMAX_ID=<remoteId> to reconnect a known
    // device rather than scan. Its health snapshots become the SAME
    // (BandTelemetry, TriageResult) records the OEM band produces, so the
    // dashboard, on-device triage and batching downstream are unchanged.
    const watchEnabled = bool.fromEnvironment('STARMAX_WATCH', defaultValue: false);
    if (watchEnabled) {
      const knownId = String.fromEnvironment('STARMAX_ID', defaultValue: '');
      final watch = StarmaxBandManager(StarmaxBandConfig(
        knownRemoteId: knownId.isEmpty ? null : knownId,
      ));
      watch.onTelemetry.listen((rec) {
        controller.onTelemetry(rec.$1, rec.$2); // dashboard + emergency
        monitor.handle(rec.$1, rec.$2); // sync + batching
      });
      // The full activity/sleep/wellness snapshot → the dashboard's activity
      // panel. Everything the watch tracks beyond the four triage vitals.
      watch.onSnapshot.listen(controller.onWearableMetrics);
      // Link state (connecting / connected / lost) drives the dashboard's "not
      // measuring" chip, so a watch out of range since morning is not mistaken
      // for a quiet one — the only other evidence would be a last reading that
      // keeps getting older.
      watch.onStatus.listen(controller.onBandLinkState);
      await watch.start();
    }

    // TODO(once paired): the OEM band + child beacon still await pairing/config:
    //   ble.onBeacon.listen((r) => controller.onChildLocation(resolveFix(r)));
    //   await ble.start();
    //
    // TODO(after sign-in): controller.configureChild(name, fences) from the backend.
  } catch (_) {
    // Degrade gracefully — the UI already rendered; retry wiring on next launch.
  }
}

/// Last HTTP status complained about, so a repeating refusal is logged once
/// rather than every 45 seconds for the life of the app.
int? _lastPollComplaint;

/// Ask the backend where the selected child is, forever, gently.
///
/// Deliberately tolerant: this runs for the life of the app, so any throw here
/// would silently end child tracking for the session. Every failure is a skipped
/// tick rather than the end of the loop — offline, a 404 because no fix has been
/// recorded yet, a child not yet selected, a malformed payload.
///
/// The observed timestamp comes from the SERVER, not from now(). A fix recorded
/// four minutes ago must read as four minutes old; calling it live is the one
/// thing a tracking screen must not do.
Future<void> _pollChildLocation(
  AppController controller,
  ApiClient api, {
  Duration every = const Duration(seconds: 45),
}) async {
  while (true) {
    await Future<void>.delayed(every);
    final childId = controller.selectedChild?.id;
    if (childId == null) continue; // nothing to track yet
    try {
      final fix = await api.lastLocation(childId);
      if (fix == null) continue; // 404: no position recorded yet
      final coords = fix['coords'];
      if (coords is! Map) continue;
      final lat = (coords['lat'] as num?)?.toDouble();
      final lng = (coords['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final observedAt = DateTime.tryParse('${fix['observedAt'] ?? ''}');
      controller.onChildLocation(Coordinates(lat, lng), at: observedAt?.toLocal());
    } on ApiException catch (e) {
      // Say WHY, once per reason. A tracking screen that stays empty with no
      // explanation is how the previous version of this hid: it looked like it
      // was waiting for a fix when nothing was ever going to arrive.
      //
      // 403 here is expected until children are synced with the backend: the
      // app creates them locally during onboarding with ids like `child-1`,
      // while the server issues UUIDs and checks ownership, so it refuses an id
      // it has never seen. See the sign-in TODO above — until then the map
      // shows only what the device itself observes.
      if (_lastPollComplaint != e.statusCode) {
        _lastPollComplaint = e.statusCode;
        debugPrint('child location: server said ${e.statusCode} for "$childId" — '
            '${e.statusCode == 403 || e.statusCode == 404 ? 'this child is not one the backend knows; '
                'local and server children are not reconciled yet' : 'will retry'}');
      }
    } catch (_) {
      // Offline, a server hiccup, a shape we did not expect. Try again next
      // tick — the alternative is that one bad reply ends tracking silently.
    }
  }
}
