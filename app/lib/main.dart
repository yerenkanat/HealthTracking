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
// Her IANA zone, for `users.timezone` — the clock the SERVER reads her quiet
// hours against. Already a dependency: notification_service uses it to point
// tz.local at the device's real zone.
import 'package:flutter_timezone/flutter_timezone.dart';

import 'data/announcements_repository.dart';
import 'data/notification_service.dart';
import 'data/content_repository.dart';
import 'data/photo_paths.dart';
import 'data/content_store.dart';
import 'data/cry_settings_repository.dart';
import 'data/emergency_help_repository.dart';
import 'data/pregnancy_weeks_repository.dart';
import 'data/vaccination_schedule_repository.dart';
import 'data/prefs_app_store.dart';
import 'data/prefs_telemetry_queue.dart';
import 'domain/geofence_alerts.dart';
import 'domain/notification_prefs.dart';
import 'domain/notification_route.dart';
import 'domain/notification_ids.dart';
import 'domain/error_log.dart';
import 'ui/widgets/error_fallback.dart';
import 'domain/cycle_log.dart';
import 'domain/health_series.dart';
import 'domain/sleep.dart';
import 'domain/cry_analysis.dart';
import 'domain/weight.dart';
import 'domain/wearable_metrics.dart';
import 'ble/starmax/starmax_ble_transport.dart';
import 'ble/watch_identity.dart' show looksLikeBleRemoteId;
import 'domain/ai_chat_service.dart';
import 'data/connectivity.dart';
import 'domain/appointment.dart';
import 'ble/calibration.dart' show BpCalibration;
import 'domain/child_emergency.dart' show ChildEmergencyInfo;
import 'domain/child_growth.dart' show GrowthPoint;
import 'domain/contraction.dart' show ContractionSessionRecord;
import 'domain/kick_session.dart' show KickSessionRecord;
import 'domain/medication.dart' show Medication;
import 'domain/newborn_log.dart' show NewbornEvent;
import 'domain/chat_controller.dart';
import 'domain/family.dart' show UserProfile, ChildProfile, PairedDevice, genderFromName;
import 'domain/health_monitor.dart';
import 'data/api_client.dart';
import 'data/shop_catalogue_cache.dart';
import 'data/server_phone_auth.dart';
import 'ui/auth/sign_in_route.dart' show apiBaseForAuth;
import 'data/sync_push.dart';
import 'data/http_transport.dart';
import 'l10n/l10n.dart';
import 'net/telemetry_batcher.dart';

/// Parse a geofence from the server's shape, or null if the row is unusable —
/// so a bad zone drops itself rather than the whole restore. (Used on sign-in.)
Geofence? _tryGeofence(Map<String, dynamic> j) {
  try {
    return Geofence.fromJson(j);
  } catch (_) {
    return null;
  }
}

/// The device's IANA zone — 'Europe/Berlin', not '+02:00' — or null.
///
/// This is what `users.timezone` on the server is set from, and what her quiet
/// hours are read against there. Cached after the first answer because it is a
/// platform channel call and every settings save would otherwise make one.
///
/// NULL RATHER THAN A GUESS on any failure. `DateTime.now().timeZoneName` is the
/// tempting fallback and it is wrong twice over: it gives an abbreviation or an
/// offset ('+05', 'CEST'), which is not an IANA name the server can resolve, and
/// an offset cannot survive her clocks changing in October. A missing key leaves
/// the server holding whatever it already had, which is the safe direction.
String? _cachedTimezone;
Future<String?> _deviceTimezone() async {
  if (_cachedTimezone != null) return _cachedTimezone;
  try {
    final tz = (await FlutterTimezone.getLocalTimezone()).identifier;
    if (tz.trim().isEmpty) return null;
    return _cachedTimezone = tz;
  } catch (_) {
    // No platform channel (a widget test), or a platform that cannot say.
    return null;
  }
}

/// Run one unit of the new-device restore, keeping its failure to itself.
///
/// Every pull is best-effort: offline, a backend that is down, or one malformed
/// row must leave the local data intact and let the next launch try again. It
/// must ALSO not take the other pulls down with it — the restores run under
/// Future.wait, which abandons its whole batch the moment any future throws.
Future<void> _restore(Future<void> Function() pull) async {
  try {
    await pull();
  } catch (_) {
    // Offline, backend down, or an unusable row — local data is intact.
  }
}

/// Parse a newborn event from the server's shape, or null if the row is unusable
/// (unknown kind / implausible duration) — so one bad row drops itself rather
/// than the whole child's log. (Used on sign-in restore.)
NewbornEvent? _tryNewborn(Map<String, dynamic> j) {
  try {
    return NewbornEvent.fromJson(j);
  } catch (_) {
    return null;
  }
}

/// Parse a growth measurement from the server's shape, or null if the row is
/// unusable (no measurement / implausible value) — so one bad row drops itself
/// rather than the whole child's curve. (Used on sign-in restore.)
GrowthPoint? _tryGrowth(Map<String, dynamic> j) {
  try {
    return GrowthPoint.fromJson(j);
  } catch (_) {
    return null;
  }
}

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

  // The pregnancy calendar, from the last server response this phone received.
  // Layered over the bundled asset, week by week — so a launch with no signal
  // shows the newest text she has ever had, and never an empty week screen.
  // The network refresh happens after runApp, like the catalogue's.
  await primePregnancyWeeksFromCache(const PrefsPregnancyWeeksCache());

  // The immunisation calendar and its catch-up window (admin frames 15/15a/15b),
  // from the last server answer this phone received. Read BEFORE first paint for
  // the same reason as the pregnancy calendar, and for a sharper one: the window
  // decides where «пора» ends and «стоит наверстать» begins on every row of the
  // vaccination screen, and applying yesterday's number for a moment is fine
  // while applying a number the back office replaced months ago is not. The
  // bundled kzSchedule stays the floor, so a phone with no signal still opens
  // the whole calendar.
  await primeVaccinationScheduleFromCache(const PrefsVaccinationScheduleCache());

  // Screen 37's emergency scenarios, same ladder and for a sharper reason: the
  // screen is opened by somebody deciding whether to call an ambulance, and it
  // must never wait on a request or come up empty. The bundled asset is the
  // floor; this puts the newest published text on top of it before first paint.
  await primeEmergencyHelpFromCache(const PrefsEmergencyHelpCache());

  // The cry detector's confidence threshold (кадр 17c), from the last answer
  // this phone received. Read BEFORE first paint because it decides whether the
  // screen NAMES a reason at all — applying yesterday's number for the first
  // few seconds of a launch is fine; applying none is not.
  await primeCryThresholdFromCache(const PrefsCryThresholdCache());

  // Рассылки from the back office, from the last response this phone received
  // (admin frame 06 → screen 39). Read BEFORE first paint for the same reason
  // as the calendar: a launch with no signal must show the message she was
  // sent, and the badge over the bell must be right on the first frame rather
  // than jumping a second later.
  //
  // A failed read is an empty list, never an exception — this feeds the same
  // screen as her child's SOS alerts, and a marketing message is not worth
  // taking that down.
  controller.onSignedOut =
      () => clearAnnouncementsCache(const PrefsAnnouncementsCache());
  controller.setAnnouncements(
      await primeAnnouncementsFromCache(const PrefsAnnouncementsCache()));

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
        // Band samples, so the demo shows what a band actually earns — which
        // for temperature is silence, not «держится ровно».
        source: ReadingSource.sensor,
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
  // a paired device. On a real build this arrives from the watch over BLE as
  // soon as a band is paired; here it is representative test data.
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

/// Screen 38 · a tapped notification, resolved to a screen.
///
/// Kept out of [bootstrapRuntime] and public so it can be driven from a test
/// with nothing but a controller and a payload string — the whole point being
/// that a payload written on the server (TypeScript) is read here, and the two
/// have no compiler between them.
///
/// Nothing here can throw: [parseNotificationPayload] resolves anything it does
/// not understand to the dashboard, and an SOS with no usable content still
/// raises the screen, because the fact that the button was pressed is the part
/// that matters.
void handleNotificationTap(AppController controller, String? payload) {
  final tap = parseNotificationPayload(payload);
  if (tap.destination == NotifyDestination.sos) {
    // Screen 21, over everything. The alert goes through mergeRemoteAlerts so
    // it also lands on the safety feed — deduplicated against the one this
    // phone may already have recorded — and that is what raises the takeover.
    controller.mergeRemoteAlerts([
      SafetyAlert(
        kind: AlertKind.sos,
        // Empty when the push did not name a child; the screen has wording for
        // that, and inventing one here is the one thing it must not do.
        childName: tap.childName,
        zoneName: tap.zoneName,
        at: tap.at ?? DateTime.now(),
      ),
    ]);
    // A merge that deduplicated against an alert already in the feed adds
    // nothing and therefore raises nothing — so ask directly as well. Tapping
    // an SOS notification must open screen 21 every time, not only the first.
    controller.raiseSosAlert(SafetyAlert(
      kind: AlertKind.sos,
      childName: tap.childName,
      zoneName: tap.zoneName,
      at: tap.at ?? DateTime.now(),
    ));
    return;
  }
  if (tap.destination == NotifyDestination.emergency) {
    // The mother's own medical emergency. The code travels in the payload, so
    // the app localizes it exactly as it does an on-device one rather than
    // showing whatever language the server composed in.
    controller.onChatEmergency(
      L10n(controller.locale).triageMessage(tap.code),
      const [],
      code: tap.code,
    );
    return;
  }
  controller.requestDestination(tap.destination);
}

/// Connects the verified spine to live sources. Kept out of the widget tree so
/// UI is testable and the app still renders if any of this is unavailable.
Future<void> bootstrapRuntime(
  AppController controller, {
  ContentStore? content,
  ContentCache? contentCache,
}) async {
  // On-device notifications for child safety alerts. Delivery is decided in one
  // place — AppController.shouldDeliverAlert — which honours the per-category
  // switches and quiet hours and NEVER holds an SOS. We re-check it here rather
  // than trusting the stream, so a future emit site that forgets the gate cannot
  // buzz a phone at 03:00, and cannot silence an emergency either.
  // Best-effort — the app works fine without it.
  try {
    final notifications = LocalNotificationService();
    await notifications.init(onTap: (payload) => handleNotificationTap(controller, payload));
    // …and the tap that STARTED the app. On a cold launch Android delivers it
    // as intent data instead of calling the response handler above, so without
    // this an SOS tapped on a phone whose app was not running — the ordinary
    // case for a notification — would open on the dashboard.
    unawaited(() async {
      final payload = await notifications.launchPayload();
      if (payload != null) handleNotificationTap(controller, payload);
    }());
    // Do NOT request permission blindly at launch. Instead let the UI ask at a
    // moment it can explain why (the reminders centre / adding a safe zone),
    // which is what the notification service's init comment intends.
    controller.attachNotificationPermission(
      request: notifications.requestPermission,
      granted: notifications.hasPermission,
    );
    controller.newAlerts.listen((alert) {
      if (!controller.shouldDeliverAlert(alert)) return;
      final l = L10n(controller.locale);
      final title = switch (alert.kind) {
        AlertKind.entered => l.t('alert_entered', {'zone': alert.zoneName}),
        AlertKind.left => l.t('alert_left', {'zone': alert.zoneName}),
        AlertKind.checkIn => l.t('alert_checkin'),
        AlertKind.sos => l.t('alert_sos'),
        AlertKind.lowBattery => l.t('alert_low_battery', {'pct': alert.zoneName}),
      };
      final isSos = alert.kind == AlertKind.sos;
      notifications.show(
        title: title,
        body: alert.childName,
        // Where a tap goes. An SOS opens screen 21 carrying the name and the
        // instant it happened; everything else opens the notification centre,
        // where that event is already waiting in the list.
        payload: isSos
            ? sosNotificationPayload(
                childName: alert.childName,
                at: alert.at,
                zoneName: alert.zoneName,
              )
            : notificationPayload(NotifyDestination.notificationCentre),
        // §2.20's bordered lock-screen alert, for the SOS alone.
        fullScreen: isSos,
      );
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
      // The signed-in session's token (stub today, Firebase ID token once
      // wired). Read fresh each request so sign-in/out takes effect immediately.
      getToken: () async => controller.authSession?.token,
      devUserId: const String.fromEnvironment('DEV_USER_ID'),
    ),
      // So the shop still has prices — and can say how old they are — on a
      // phone with no signal.
      catalogueCache: const PrefsShopCatalogueCache(),
    );

    // Her mail, on demand. Defined and wired here — before the first `await`
    // below, so a sign-in that happens while the catalogue is still downloading
    // already has somewhere to go — because the fetch needs the ApiClient and
    // the prefs cache, and the controller is pure Dart and owns neither.
    Future<void> pullAnnouncements() async {
      if (controller.authSession == null) return;
      final fresh = await refreshAnnouncementsFromApi(
          api: api, cache: const PrefsAnnouncementsCache());
      if (fresh != null) {
        controller.setAnnouncements(fresh);
        debugPrint('announcements: ${fresh.length} from the server');
      }
    }
    controller.onRefreshAnnouncements = pullAnnouncements;

    // Ask the server whether this build is still supported. A raised floor
    // blocks the app behind the force-update screen; offline or a failure here
    // leaves the gate open (never strand a user who cannot reach the server).
    unawaited(() async {
      try {
        final v = await api.getAppVersion();
        controller.applyMinBuild(v.minBuild);
      } catch (_) {
        // Offline / backend down — do not block.
      }
    }());

    // Pull whatever the back-office has published. The app already showed the
    // cached or bundled catalogue at first paint, so this only ever upgrades
    // what is on screen — and a failure quietly leaves that in place.
    if (content != null) {
      final fresh = await refreshCatalogFromApi(api: api, cache: contentCache);
      if (fresh != null) content.adopt(fresh, CatalogSource.api);
    }

    // The pregnancy calendar, same shape: the asset is already on screen, so
    // this only ever upgrades it, week by week, and a failure leaves it alone.
    // Frame 14a/14b — without this the back office can edit week 22 all day
    // and no phone ever finds out.
    unawaited(() async {
      final n = await refreshPregnancyWeeksFromApi(
          api: api, cache: const PrefsPregnancyWeeksCache());
      if (n != null) debugPrint('pregnancy weeks: refreshed $n week(s) from the server');
    }());

    // The immunisation calendar, same shape. Frames 15/15a/15b — without this
    // the back office can move the second pneumococcal dose all day and no phone
    // ever finds out, which is exactly what it did before this call existed.
    // Unauthenticated, so it runs on a fresh install too.
    unawaited(() async {
      final n = await refreshVaccinationScheduleFromApi(
          api: api, cache: const PrefsVaccinationScheduleCache());
      if (n != null) debugPrint('vaccination schedule: refreshed $n vaccine(s) from the server');
    }());

    // The emergency scenarios, same shape. Frame 16b — without this the back
    // office can correct a first-aid instruction all day and no phone ever
    // finds out. Unauthenticated, so it runs on a fresh install too.
    unawaited(() async {
      final n = await refreshEmergencyHelpFromApi(
          api: api, cache: const PrefsEmergencyHelpCache());
      if (n != null) debugPrint('emergency help: refreshed $n scenario(s) from the server');
    }());

    // The cry threshold, same shape. Кадр 17c — without this the back office
    // can raise the bar for naming a reason all day and no phone finds out, and
    // the number goes back to needing a store rollout. Unauthenticated, so it
    // runs on a fresh install too.
    unawaited(() async {
      final v = await refreshCryThresholdFromApi(
          api: api, cache: const PrefsCryThresholdCache());
      if (v != null) debugPrint('cry: threshold from the server is $v');
    }());

    // The рассылки, same shape: the cached copy is already on screen, so this
    // only ever upgrades it, and a failure — including the 503 the route
    // answers before migration 037 — leaves it alone. Frame 06: without this
    // the back office can write to forty thousand mothers and no phone ever
    // finds out.
    //
    // Only ever attempted with a session. `/announcements` is user-scoped, and
    // an unauthenticated call would answer 401, which this treats as "keep what
    // we have" — correct, but a request worth not making.
    //
    // Startup is NOT the only time this runs. On a fresh install there is no
    // session at this point — she has not onboarded yet — so this pull returns
    // immediately, and if it were the only one her notification centre would
    // stay empty until the next cold launch. The same closure is therefore
    // handed to the controller, which calls it on sign-in, on resume and when
    // the centre is opened.
    unawaited(pullAnnouncements());

    // Offline-first batcher → flushes batches to /ingest/batch. The queue is
    // mirrored to disk (shared_preferences) so telemetry buffered while offline —
    // an emergency reading queued the instant before a crash included — survives
    // an app kill and is delivered on the next launch, instead of being lost.
    final telemetryQueue = PrefsTelemetryQueue();
    final batcher = TelemetryBatcher(BatcherConfig(
      maxBatch: 25,
      maxDelay: const Duration(seconds: 30),
      // The reply was discarded here. `/ingest/batch` answers 200 with a tally
      // — and a batch it stored nothing from looks identical to a delivered one
      // unless somebody reads `rejected`. Now it is read, and a refusal reaches
      // the error log support can see.
      flush: (items) async {
        final summary = await api.ingestBatch(items.map((i) => i.toJson()).toList());
        reportIngest(summary, errorLog: controller.errorLog);
      },
      persist: telemetryQueue.save,
      restore: telemetryQueue.load,
    ));
    await batcher.init();

    // HealthMonitor: on-device triage → batcher (urgent bypass on emergencies).
    // onEmergency forwards to the controller (note: HealthMonitor's signature is
    // (triage, telemetry); AppController.onTelemetry is (telemetry, triage)).
    final monitor = HealthMonitor(
      // The band she actually paired, asked for at send time. This was the
      // compile-time BAND_ID, defaulting to the string 'band-unpaired' — an id
      // no device registry has ever contained, so the server could attribute
      // none of it and dropped every reading as it arrived. The define stays as
      // a last resort for a bench rig with no pairing flow.
      resolveDeviceId: () => controller.pairedBandId ?? '',
      deviceId: const String.fromEnvironment('BAND_ID', defaultValue: 'band-unpaired'),
      enqueue: (t, {required urgent}) => batcher.enqueueTelemetry(t, urgent: urgent),
      onEmergency: (triage, t) => controller.onTelemetry(t, triage),
    );

    controller.attachRuntime(monitor: monitor, batcher: batcher, api: api);

    // Claim the number she typed during onboarding, so finishing setup signs
    // her in rather than asking again for something she just gave. The same
    // provider the sign-in screen uses — one answer to "what does a session
    // cost", not two.
    controller.onPhoneSignIn = (phone, displayName) async {
      final provider = ServerPhoneAuthProvider(
          baseUrl: apiBaseForAuth, now: DateTime.now);
      final challenge = await provider.requestCode(phone);
      // Nothing to type while codes are switched off; when they are switched
      // on this returns early and the checklist asks her to sign in properly.
      if (provider.requiresCode) return null;
      return provider.verifyCode(challenge, '');
    };

    // Connectivity: drive the offline banner, and flush the batcher the moment
    // the network returns — the onConnectivityRestored hook that nothing called,
    // so a backlog built up offline used to wait for the next timer tick.
    try {
      final connectivity = PlatformConnectivity();
      controller.setOnline(await connectivity.isOnline());
      connectivity.onlineChanges.listen((online) {
        final wasOnline = controller.isOnline;
        controller.setOnline(online);
        if (online && !wasOnline) batcher.onConnectivityRestored();
      });
    } catch (_) {
      // Connectivity plugin unavailable (e.g. a headless run) — assume online.
    }

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

    // Appointment sync — only once she is signed in (the routes are user-scoped).
    // Push local edits to the server as a backup, and pull on start so a fresh
    // sign-in on a new phone restores her visits. Local stays the source of
    // truth; a failed sync never blocks a local edit.
    if (controller.isSignedIn) {
      String iso(DateTime at) => at.toUtc().toIso8601String();
      // Wake-day as a plain yyyy-MM-dd, the shape the /sleep endpoint expects.
      String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      // One night → the /sleep body. A manual night has no stage split, so its
      // whole asleep total goes in as light sleep, keeping the admin total right.
      Future<void> pushSleep(SleepSummary s) => api.putSleep(
            night: isoDay(s.night),
            deepMin: s.deepMin,
            remMin: s.remMin,
            lightMin: s.asleepMin - s.deepMin - s.remMin,
            awakeMin: s.awakeMin,
          );

      // Profile backup (push-only): send edits, and the current profile once, so
      // it survives a device change. Only when there is a name to save.
      Future<void> pushProfile(UserProfile p) => p.displayName.trim().isEmpty
          ? Future<void>.value()
          // No phone: it identifies the account rather than describing it, and
          // the server keeps the one sign-in recorded (see putProfile).
          : api.putProfile(
              displayName: p.displayName,
              dueDate: p.dueDate,
              birthDate: p.birthDate,
              city: p.city,
              locale: controller.locale.name,
              doctorPhone: p.doctorPhone,
              // Screen 37's dispatcher card. Backed up like everything else
              // here: the one moment she needs it is the one moment she cannot
              // be retyping it after a reinstall.
              address: p.address,
              // Baselines are user-level settings that ride the profile backup;
              // read the raw (nullable) values so an unset default isn't sent as
              // a chosen one.
              avgCycleLength: controller.cycleBaselineDays,
              avgPeriodLength: controller.periodBaselineDays,
            );
      controller.attachProfileSync(pushProfile);
      unawaited(pushProfile(controller.profile));

      controller.attachAppointmentSync(
        upsert: (a) => api.putAppointment(id: a.id, title: a.title, at: iso(a.at), note: a.note),
        delete: (id) => api.deleteAppointment(id),
      );

      // Her notification switches and quiet hours — frame 25, screen 39.
      //
      // Three of the four categories gate notifications the SERVER raises: a
      // zone crossing derived from a tracker fix this phone never saw, an
      // operator's answer, a рассылка. Until this hook existed the switches
      // were written to SharedPrefs and read by nothing else, so «Зоны: выкл»
      // and quiet hours 22:00–07:00 stopped exactly the notifications this
      // phone raised for itself and none of the ones it did not.
      //
      // NO first-sync push here. That is the obvious next line and it is a
      // data-loss bug: on a fresh install this phone holds the DEFAULTS, and
      // pushing them before the restore below has run would erase the quiet
      // hours she set on her old phone. The upload happens after the GET, in
      // the restore batch, and only when the two disagree.
      //
      // HER ZONE TRAVELS WITH THE WINDOW. `users.timezone` is what the server
      // reads her quiet hours against, and nothing had ever written it: the
      // column sat at its 'Asia/Almaty' default for everybody, so a mother in
      // Berlin or Istanbul — the app ships ru/kk/en and there is a diaspora on
      // all three — had 22:00–07:00 applied three or four hours early. A
      // geofence push at 22:30 her time went out and one at 06:00 was held:
      // quiet hours exactly wrong rather than merely absent.
      //
      // Sent as an IANA NAME, never an offset: the server has to survive her
      // clocks changing in October, and '+02:00' cannot.
      controller.attachNotificationPrefsSync(
        push: (p) async {
          final zone = await _deviceTimezone();
          await api.putNotificationSettings({
            ...p.toApiJson(),
            // Omitted rather than guessed when the platform cannot say. The
            // server leaves the stored zone alone for a missing key, which is
            // the safe direction: a guess would overwrite a good one.
            if (zone != null) 'timezone': zone,
          });
        },
      );

      // Manual safety events — SOS and check-in. The one sync that is not a
      // backup: it is how an SOS pressed on this phone reaches the back-office
      // safety feed and the rest of the family at all. Alerts are keyed on the
      // child's NAME in the app and on their id on the server, so an event for
      // a child the server has never seen is dropped rather than guessed at.
      //
      // No first-sync replay of the existing feed: these already happened, and
      // re-posting a month of old SOS presses would re-alarm everybody the
      // moment somebody signs in on a new phone.
      controller.attachAlertSync(upsert: (alert) async {
        final match = controller.children
            .where((ch) => ch.name.isNotEmpty && ch.name == alert.childName);
        if (match.isEmpty) return;
        await pushed(
          'safety alert',
          () => api.postAlert(
            childId: match.first.id,
            kind: alert.kind.name,
            zoneName: alert.zoneName,
            at: iso(alert.at),
          ),
          errorLog: controller.errorLog,
        );
      });

      // Push-only sleep sync, so the admin wellness view mirrors her nights.
      controller.attachSleepSync(upsert: pushSleep);
      // First-sync push: send the nights we already have so a fresh sign-in
      // does not start the wellness view empty.
      for (final s in controller.sleepNights) {
        unawaited(pushSleep(s));
      }

      // Push-only cry-analysis history, so it survives a reinstall / new device.
      Future<void> pushCry(CryResult c) => api.putCryResult(
            at: c.at.toIso8601String(), reason: c.reason, confidence: c.confidence);
      controller.attachCrySync(upsert: pushCry);
      for (final c in controller.cryHistory) {
        unawaited(pushCry(c));
      }

      // «Это было верно?» (кадр 17c). Wrapped in `pushed` rather than fired and
      // forgotten: a verdict is the only ground truth this product has about
      // why a baby cried, and one that silently 404s is one nobody can ever
      // recover — the screen has already thanked her for it.
      controller.attachCryVerdictSync(
        push: (c) => pushed(
            'cry verdict',
            () => api.postCryVerdict(
                at: c.at.toIso8601String(),
                verdict: c.verdict!,
                actualReason: c.actualReason),
            errorLog: controller.errorLog),
      );
      // The verdicts already sitting in a history recorded while signed out.
      // Without this they reach the server only if she happens to rate again.
      for (final c in controller.cryHistory) {
        if (c.verdict != null) {
          unawaited(pushed(
              'cry verdict',
              () => api.postCryVerdict(
                  at: c.at.toIso8601String(),
                  verdict: c.verdict!,
                  actualReason: c.actualReason),
              errorLog: controller.errorLog));
        }
      }

      // Push-only women's-health day-log sync (flow / mood / symptoms / kicks),
      // so the admin wellness diary mirrors hers.
      controller.attachCycleSync(
          upsert: (log) => pushed('day log', () => api.putDayLog(log.toJson()), errorLog: controller.errorLog));
      for (final log in controller.dayLogs.values) {
        if (log.isNotEmpty) {
          unawaited(pushed('day log', () => api.putDayLog(log.toJson()), errorLog: controller.errorLog));
        }
      }

      // Push-only child sync, so the back-office kids dashboard is built from
      // real children (name / gender / DOB).
      //
      // Legacy 'child-1' ids used to fail the server's UUID check and be
      // dropped in silence — this comment used to describe that as a permanent
      // condition. They are re-issued on load now (domain/legacy_ids.dart), and
      // a refusal goes through pushed(), so the next contract mismatch shows up
      // on the first run rather than after months of an empty dashboard.
      Map<String, dynamic> childBody(ChildProfile ch) => {
            'id': ch.id,
            'name': ch.name,
            if (ch.gender != null) 'gender': ch.gender!.name,
            if (ch.dateOfBirth != null) 'dateOfBirth': isoDay(ch.dateOfBirth!),
          };
      controller.attachChildSync(
          upsert: (ch) => pushed('child', () => api.putChild(childBody(ch)), errorLog: controller.errorLog));
      for (final ch in controller.children) {
        unawaited(pushed('child', () => api.putChild(childBody(ch)), errorLog: controller.errorLog));
      }

      // Safe-zone (geofence) sync. The server groups zones under the child's id,
      // so a zone can only sync once its child has (both use UUID ids now).
      Map<String, dynamic> geofenceBody(Geofence g) => {
            'id': g.id,
            'name': g.name,
            'shape': g.shape.name,
            if (g.shape == GeofenceShape.circle) ...{
              'center': {'lat': g.center!.lat, 'lng': g.center!.lng},
              'radiusM': g.radiusM,
            } else
              'vertices': [for (final v in g.vertices!) {'lat': v.lat, 'lng': v.lng}],
          };
      controller.attachGeofenceSync(
        upsert: (childId, g) => api.putGeofence(childId, geofenceBody(g)),
        delete: (id) => api.deleteGeofence(id),
      );
      for (final ch in controller.children) {
        for (final g in ch.geofences) {
          unawaited(pushed('safe zone', () => api.putGeofence(ch.id, geofenceBody(g)), errorLog: controller.errorLog));
        }
      }

      // BP-calibration sync. No first-sync push: an existing local calibration
      // stores only the offset, and the server needs the raw cuff+ppg the offset
      // can't be split back into — so only NEW calibrations (which carry the raw
      // values) sync. The next one she records reaches the clinician in full.
      controller.attachBpCalibrationSync(
        upsert: ({required cuffSystolic, required cuffDiastolic, required ppgSystolic, required ppgDiastolic, required at}) =>
            api.submitBpCalibration(
              cuffSystolic: cuffSystolic,
              cuffDiastolic: cuffDiastolic,
              ppgSystolic: ppgSystolic,
              ppgDiastolic: ppgDiastolic,
              measuredAt: iso(at),
            ),
      );

      // Retry a calibration whose push never landed. Every other synced type is
      // re-pushed wholesale at startup, so a failure there heals itself; this
      // one is held as a single pending record instead, because it is the only
      // sync carrying raw values that cannot be rebuilt from what is stored.
      unawaited(controller.flushPendingBpCalibration());

      // And the sign-outs the server never heard about. Same reasoning, higher
      // stakes: a revoke that never landed leaves a working key to her account
      // on a phone she has already stopped using, for ninety days, and nothing
      // else will ever retry it.
      unawaited(controller.flushPendingLogouts());

      // Newborn care sync (feed/diaper/sleep), so the admin sees the pattern.
      controller.attachNewbornSync(
        upsert: (childId, e) => api.putNewbornEvent(childId, e.toJson()),
      );
      for (final ch in controller.children) {
        for (final e in controller.newbornLogFor(ch.id)) {
          unawaited(api.putNewbornEvent(ch.id, e.toJson()));
        }
      }

      // Child growth sync (weight/height), so the pediatric growth curve reaches
      // the clinician like the mother's weight does.
      controller.attachGrowthSync(
        upsert: (childId, p) => api.putGrowth(childId, p.toJson()),
      );
      for (final ch in controller.children) {
        for (final p in controller.growthFor(ch.id)) {
          unawaited(pushed('growth measurement', () => api.putGrowth(ch.id, p.toJson()), errorLog: controller.errorLog));
        }
      }

      // Vaccination-record sync (parent-marked), so the clinician sees which
      // shots are recorded. Push-only + first-sync.
      controller.attachVaccineSync(
        upsert: (childId, key, done) => api.putVaccine(childId, key, done: done),
      );
      for (final ch in controller.children) {
        for (final key in controller.vaccinesDoneFor(ch.id)) {
          unawaited(pushed('vaccination', () => api.putVaccine(ch.id, key, done: true), errorLog: controller.errorLog));
        }
      }

      // Child emergency medical-ID sync. Send ALL fields (not just non-empty) so
      // clearing one syncs; the server bounds each.
      Map<String, dynamic> medicalIdBody(ChildEmergencyInfo e) => {
            'bloodType': e.bloodType, 'allergies': e.allergies, 'conditions': e.conditions,
            'medications': e.medications, 'doctorName': e.doctorName, 'doctorPhone': e.doctorPhone,
            'contactName': e.contactName, 'contactPhone': e.contactPhone, 'notes': e.notes,
          };
      controller.attachEmergencySync(
        upsert: (childId, e) => api.putChildEmergency(childId, medicalIdBody(e)),
      );
      for (final ch in controller.children) {
        final e = controller.emergencyInfoFor(ch.id);
        if (!e.isEmpty) unawaited(api.putChildEmergency(ch.id, medicalIdBody(e)));
      }

      // Push-only weight sync, so the admin wellness view mirrors her trend.
      controller.attachWeightSync(upsert: (w) => api.putWeight(date: w.date, kg: w.kg));
      for (final w in controller.weights) {
        unawaited(pushed('weight', () => api.putWeight(date: w.date, kg: w.kg), errorLog: controller.errorLog));
      }

      // Device sync (register + unregister), so the admin fleet shows real
      // paired bands/tags. childId is a UUID for tags; null for a band.
      controller.attachDeviceSync(
        upsert: (d) => api.putDevice(d.toJson()),
        delete: (id) => api.deleteDevice(id),
        // The way out of a «not ours» refusal. Wired here, or the sheet, the
        // controller method and the route are three finished pieces with
        // nothing joining them — which is exactly the defect this feature was
        // built to fix.
        claim: (code) => api.claimDevice(code),
      );
      for (final d in controller.devices) {
        unawaited(pushed('device', () => api.putDevice(d.toJson()), errorLog: controller.errorLog));
      }

      // Timed-session sync: fetal movement + labour timing → clinician trend.
      controller.attachSessionSync(
        kick: (s) => api.putKickSession(s.toJson()),
        contraction: (s) => api.putContractionSession(s.toJson()),
      );
      for (final s in controller.kickSessions) {
        unawaited(api.putKickSession(s.toJson()));
      }
      for (final s in controller.contractionSessions) {
        unawaited(api.putContractionSession(s.toJson()));
      }

      // Medication sync (upsert + delete), so staff see what she is taking.
      Map<String, dynamic> medBody(Medication m) =>
          {'id': m.id, 'name': m.name, 'dose': m.dose, 'perDay': m.perDay};
      controller.attachMedicationSync(
        upsert: (m) => api.putMedication(medBody(m)),
        delete: (id) => api.deleteMedication(id),
      );
      for (final m in controller.medications) {
        unawaited(api.putMedication(medBody(m)));
      }

      // Medication adherence sync (doses taken per day), so the clinician sees
      // whether she is keeping to each medication. Push-only + first-sync.
      controller.attachDoseSync(
        upsert: (medId, day, count) => api.putDose(medId, {'date': isoDay(day), 'count': count}),
      );
      controller.medLog.forEach((day, perMed) {
        perMed.forEach((medId, count) {
          if (count > 0) unawaited(api.putDose(medId, {'date': day, 'count': count}));
        });
      });
      // New-device restore: pull back everything the server has that this
      // install doesn't, so a reinstall or a new phone is not an empty app.
      //
      // These run CONCURRENTLY. Written as a serial chain of awaits it was ten
      // round trips plus two more per child, each one waiting on the last — on
      // mobile data that is several seconds of a blank app before her own data
      // appears, and it grew every time another data type was added. Nothing
      // here depends on anything else here: each pull owns a different part of
      // the controller, and every merge is add-missing-by-key with local
      // winning, so order cannot change the result.
      //
      // _restore() keeps each unit's failure to itself. Future.wait aborts its
      // whole batch on the first error, so without it one endpoint being down
      // would silently discard every restore that had not finished yet.
      await Future.wait([
        // Her profile backup — name, city, birth date, and the DUE DATE that
        // drives the whole pregnancy timeline. Adopted only onto an empty
        // profile (see mergeRemoteProfile); a device already in use keeps its own.
        _restore(() async {
          final p = await api.getProfile();
          if (p == null) return;
          DateTime? day(Object? v) => v is String ? DateTime.tryParse(v) : null;
          // The server stores normalizePhone() output: DIGITS ONLY, never a
          // leading '+'. This matched `^\+7(\d{10})$`, so it never matched at
          // all and her number restored as blank on every reinstall — «Профиль»
          // and «Настройки» both showed it empty.
          //
          // It used to work by accident: the app pushed the '+7…' form up in
          // PUT /profile and read its own writing back. That push was exactly
          // the hole that let one account claim another's number, and removing
          // it left this parse with nothing to match. Both forms are accepted
          // now — the stored one, and the older rows written before the fix.
          final phone = (p['phone'] as String?) ?? '';
          final m = RegExp(r'^\+?7(\d{10})$').firstMatch(phone);
          controller.mergeRemoteProfile(UserProfile(
            displayName: (p['displayName'] as String?) ?? '',
            phoneNumber: m != null ? m.group(1)! : '', // dialCode defaults to +7
            dueDate: day(p['dueDate']),
            birthDate: day(p['birthDate']),
            city: (p['city'] as String?) ?? '',
            doctorPhone: (p['doctorPhone'] as String?) ?? '',
            address: (p['address'] as String?) ?? '',
          ));
          // The women's-health baselines ride the same backup but live outside
          // the profile object, so restore them separately (local still wins).
          controller.mergeRemoteCycleBaseline(
            cycle: (p['avgCycleLength'] as num?)?.toInt(),
            period: (p['avgPeriodLength'] as num?)?.toInt(),
          );
        }),
        _restore(() async {
          final remote = await api.getAppointments();
          controller.mergeRemoteAppointments([
            for (final m in remote)
              Appointment(
                id: m['id'] as String,
                title: (m['title'] as String?) ?? '',
                at: DateTime.parse(m['at'] as String),
                note: (m['note'] as String?) ?? '',
              ),
          ]);
          // First-sync push: send anything local the server does not have yet.
          for (final a in controller.appointments) {
            unawaited(api.putAppointment(id: a.id, title: a.title, at: iso(a.at), note: a.note));
          }
        }),

        // Children, with each child's zones and medical-ID fanned out in
        // parallel rather than two more sequential trips per child.
        _restore(() async {
          final remoteKids = await api.getChildren();
          final zones = <String, List<Geofence>>{};
          final medicalIds = <String, ChildEmergencyInfo>{};
          await Future.wait([
            for (final m in remoteKids)
              for (final pull in [
                () async {
                  final id = m['id'] as String;
                  zones[id] = [
                    for (final g in await api.getChildGeofences(id))
                      if (_tryGeofence(g) case final z?) z,
                  ];
                },
                () async {
                  final id = m['id'] as String;
                  final card = await api.getChildEmergency(id);
                  if (card != null) medicalIds[id] = ChildEmergencyInfo.fromJson(card);
                },
              ])
                _restore(pull), // one child's zones failing must not lose the rest
          ]);
          controller.mergeRemoteChildren([
            for (final m in remoteKids)
              ChildProfile(
                id: m['id'] as String,
                name: (m['name'] as String?) ?? '',
                gender: genderFromName(m['gender'] as String?),
                dateOfBirth:
                    m['dateOfBirth'] is String ? DateTime.tryParse(m['dateOfBirth'] as String) : null,
                geofences: zones[m['id'] as String] ?? const [],
              ),
          ]);
          // After the children exist, restore each child's medical-ID (local wins).
          medicalIds.forEach(controller.mergeRemoteEmergency);
        }),

        _restore(() async {
          controller.mergeRemoteMedications([
            for (final m in await api.getMedications())
              Medication(
                id: m['id'] as String,
                name: (m['name'] as String?) ?? '',
                dose: (m['dose'] as String?) ?? '',
                perDay: (m['perDay'] as num?)?.toInt() ?? 1,
              ),
          ]);
        }),

        // Health history: her weight/sleep trends and the cycle log that drives
        // the predictions.
        _restore(() async => controller
            .mergeRemoteWeights([for (final w in await api.getWeight()) WeightEntry.fromJson(w)])),
        _restore(() async => controller
            .mergeRemoteSleep([for (final n in await api.getSleep()) SleepSummary.fromJson(n)])),
        // Her baby-cry-analysis history, so the log isn't lost on a new phone.
        _restore(() async => controller
            .mergeRemoteCry([for (final r in await api.getCryResults()) CryResult.fromJson(r)])),
        // Her hand-entered vitals/glucose (device-less rows only), so a typed
        // cuff/glucometer history is not lost on a new phone.
        _restore(() async => controller
            .mergeRemoteManualVitals([for (final r in await api.getManualVitals()) HealthSample.fromJson(r)])),
        _restore(() async {
          final days = await api.getDayLogs(from: '1970-01-01', to: '2999-12-31');
          controller.mergeRemoteDayLogs([for (final d in days) DayLog.fromJson(d)]);
        }),

        // Her notification switches and quiet hours (frame 25 / screen 39), so
        // a new phone stops buzzing at 03:00 without her setting them again.
        _restore(() async {
          final raw = await api.getNotificationSettings();
          // Null = the server could not answer (unmigrated database). Keep what
          // this phone holds and retry next launch; adopting invented defaults
          // over something she chose is the one outcome worse than not syncing.
          if (raw == null) return;
          final remote = NotificationPrefs.fromJson(raw);
          // Local wins unless this install is untouched — see
          // mergeRemoteNotificationPrefs for why "untouched" and not "present".
          controller.mergeRemoteNotificationPrefs(remote);
          // First-sync push, AFTER the merge and only on a real disagreement:
          // an account that predates the server half uploads what she already
          // chose. Doing it before the merge would push this phone's defaults
          // over her real settings, which is the whole reason it is here and
          // not beside attachNotificationPrefsSync.
          if (controller.notificationPrefs != remote) {
            controller.syncNotificationPrefs();
          }
        }),

        // Paired trackers/bands, the pregnancy timing history, and the baby log.
        _restore(() async => controller
            .mergeRemoteDevices([for (final d in await api.getDevices()) PairedDevice.fromJson(d)])),
        _restore(() async => controller.mergeRemoteKickSessions(
            [for (final s in await api.getKickSessions()) KickSessionRecord.fromJson(s)])),
        _restore(() async => controller.mergeRemoteContractionSessions(
            [for (final s in await api.getContractionSessions()) ContractionSessionRecord.fromJson(s)])),
        _restore(() async {
          final byChild = <String, List<NewbornEvent>>{};
          for (final e in await api.getNewbornEvents()) {
            final childId = e['childId'] as String?;
            if (childId == null) continue;
            if (_tryNewborn(e) case final ev?) (byChild[childId] ??= []).add(ev);
          }
          controller.mergeRemoteNewborn(byChild);
        }),

        // The weekly BP calibration, so a new phone keeps correcting the band's
        // blood-pressure readings instead of reporting raw PPG until she
        // re-calibrates.
        _restore(() async {
          final cal = await api.getBpCalibration();
          if (cal != null) controller.mergeRemoteBpCalibration(BpCalibration.fromJson(cal));
        }),

        // Each child's growth curve (weight/height), keyed by the server childId
        // — no name mapping needed, so it belongs in the batch.
        _restore(() async {
          final byChild = <String, List<GrowthPoint>>{};
          for (final g in await api.getGrowth()) {
            final childId = g['childId'] as String?;
            if (childId == null) continue;
            if (_tryGrowth(g) case final p?) (byChild[childId] ??= []).add(p);
          }
          controller.mergeRemoteGrowth(byChild);
        }),

        // Medication adherence, so a new phone keeps the doses-taken history the
        // clinician reads against each target.
        _restore(() async {
          final rows = <({String medId, DateTime day, int count})>[];
          for (final d in await api.getDoses()) {
            final medId = d['medId'] as String?;
            final date = d['date'] as String?;
            final count = (d['count'] as num?)?.toInt() ?? 0;
            if (medId == null || date == null) continue;
            final day = DateTime.tryParse(date);
            if (day == null) continue;
            rows.add((medId: medId, day: day, count: count));
          }
          controller.mergeRemoteDoses(rows);
        }),

        // The vaccination record (parent-marked), keyed by the server childId.
        _restore(() async {
          final byChild = <String, Set<String>>{};
          for (final v in await api.getVaccines()) {
            final childId = v['childId'] as String?;
            final key = v['vaccineKey'] as String?;
            if (childId == null || key == null) continue;
            (byChild[childId] ??= {}).add(key);
          }
          controller.mergeRemoteVaccines(byChild);
        }),
      ]);

      // Server-detected safety alerts — a tracker-tag crossing the phone never
      // saw, or one detected while the app was closed. Runs AFTER the batch, not
      // inside it: the alerts carry a childId the server assigned, and mapping it
      // back to a name needs the children the batch above just restored. Without
      // that ordering a fresh install would drop every alert as "unknown child".
      await _restore(() async {
        final nameById = {for (final ch in controller.children) ch.id: ch.name};
        final alerts = <SafetyAlert>[];
        for (final a in await api.getAlerts()) {
          final name = nameById[a['childId'] as String?];
          if (name == null) continue; // can't attribute → don't invent a child
          alerts.add(SafetyAlert(
            kind: alertKindFromName(a['kind'] as String?),
            childName: name,
            zoneName: (a['zoneName'] as String?) ?? '',
            at: DateTime.parse(a['at'] as String),
          ));
        }
        controller.mergeRemoteAlerts(alerts);
      });
    }

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

    // The Starmax / RunmeFit health watch.
    //
    // Started when — and only when — this account has a paired band. That is a
    // RUNTIME condition, read from the device list she built by pairing, and it
    // has to be: this used to be a compile-time `bool.fromEnvironment` gate that
    // no build script in the repository ever set. Every APK the owner has
    // installed carried the entire BLE stack as dead code and said nothing, so a
    // watch on her wrist was simply never spoken to. The define is deleted
    // rather than defaulted to true, because a default-on scan charges the
    // majority who own no watch for a radio they never use — the very cost the
    // define was invented to avoid. No paired band, no scan.
    //
    // Its health snapshots become the SAME (BandTelemetry, TriageResult) records
    // the OEM band produces, so the dashboard, on-device triage and batching
    // downstream are unchanged.
    StarmaxBandManager? watch;
    Future<void> startWatchIfPaired() async {
      if (watch != null || !controller.hasPairedBand) return;
      final bandId = controller.pairedBandId!;
      final w = StarmaxBandManager(StarmaxBandConfig(
        // The id she picked while pairing IS a BLE remote id — the onboarding
        // scan reports it — so reconnect straight to it and skip the scan. A
        // serial claimed by code is not, and the manager scans for that instead.
        knownRemoteId: looksLikeBleRemoteId(bandId) ? bandId : null,
      ));
      watch = w;
      w.onTelemetry.listen((rec) {
        controller.onTelemetry(rec.$1, rec.$2); // dashboard + emergency
        monitor.handle(rec.$1, rec.$2); // sync + batching
      });
      // The full activity/sleep/wellness snapshot → the dashboard's activity
      // panel. Everything the watch tracks beyond the four triage vitals.
      w.onSnapshot.listen(controller.onWearableMetrics);
      // The days the watch stored while the app was closed — the week that was
      // sitting on her wrist and being overwritten unread. Goes to the chart
      // series, the sleep history and the backend, all through the controller.
      w.onHistory.listen(controller.onWearableHistory);
      // Link state (connecting / connected / lost) drives the dashboard's "not
      // measuring" chip, so a watch out of range since morning is not mistaken
      // for a quiet one — the only other evidence would be a last reading that
      // keeps getting older.
      w.onStatus.listen(controller.onBandLinkState);
      await w.start();
    }

    // Now, if a band is already paired…
    await startWatchIfPaired();
    // …and the moment one is paired later. Pairing happens during onboarding and
    // from the settings sheet, both AFTER this wiring has run, so a check made
    // only here would leave the watch silent until the next cold launch — the
    // first thing a new owner does with her watch would appear not to work.
    controller.changes.listen((_) => unawaited(startWatchIfPaired()));

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
