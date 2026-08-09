/// Home shell — bottom-nav container for the two primary journeys:
/// the mother's health dashboard and the child's tracking map. Rebuilds on
/// AppController changes via its `changes` stream.
library;


import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../app/app_controller.dart';
import '../core/geofence.dart';
import '../domain/appointment.dart' show nextAppointment;
import '../domain/child_tracker_state.dart' show currentZone;
import '../domain/geofence_alerts.dart';
import '../domain/hydration.dart';
import '../domain/setup_checklist.dart';
import '../domain/weekly_digest.dart';
import '../l10n/l10n.dart';
import '../l10n/l10n_scope.dart';
import 'advisor/advisor_screen.dart';
import 'chat/assistant_chat_screen.dart';
import 'ds_widgets.dart';
import 'theme.dart';
import 'appointments/appointments_screen.dart';
import 'auth/sign_in_route.dart';
import 'calendar/antenatal_plan_screen.dart';
import 'calendar/kick_session_screen.dart';
import 'calendar/day_log_sheet.dart';
import 'calendar/pregnancy_weight_screen.dart';
import '../domain/weight.dart';
import '../domain/child_development.dart';
import '../domain/family.dart';
import '../domain/cycle_predictions.dart';
import '../domain/cycle_insights.dart';
import 'calendar/womens_health_screen.dart';
import 'dashboard/health_dashboard_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/timeline_content.dart';
import 'content/lesson_player_screen.dart';
import 'content/timeline_content_screen.dart';
import 'dashboard/log_sleep_sheet.dart';
import 'dashboard/log_vitals_sheet.dart';
import 'dashboard/water_history_screen.dart';
import 'profile/family_access_screen.dart';
import 'profile/my_order_screen.dart';
import 'shop/shop_screen.dart';
import 'profile/profile_screen.dart';
import 'tracking/alerts_screen.dart';
import 'tracking/notification_centre_screen.dart';
import '../domain/day_history.dart';
import '../domain/family_access.dart';
import '../domain/my_order.dart';
import 'tracking/child_map_screen.dart';
import 'tracking/day_history_screen.dart';
import 'tracking/family_sheets.dart';
import 'tracking/zones_screen.dart';

/// Google Maps needs a real API key to render. Build with
/// `--dart-define=MAPS_ENABLED=true` once android/app has a valid key; otherwise
/// the tracking tab shows a clean placeholder instead of a black map surface.
const bool _mapsEnabled = bool.fromEnvironment('MAPS_ENABLED', defaultValue: false);

class HomeShell extends StatefulWidget {
  final AppController controller;

  /// The content catalogue in use — authored asset or seeded fallback.
  final ContentCatalog catalog;
  const HomeShell({super.key, required this.controller, required this.catalog});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final loc = c.childLocation;
    // How long the child has been in their current zone (from the alert feed).
    final curZone = loc == null ? null : currentZone(loc.coords, c.geofences);
    final zoneEnteredAt = curZone == null ? null : zoneEntryTime(c.alerts, c.childName, curZone);

    final l = L10nScope.of(context);

    final pages = [
      HealthDashboardView(
        samples: c.samples,
        sleepNights: c.sleepNights,
        greetingName: c.displayName,
        photoPath: c.profile.photoPath,
        currentLocale: c.locale,
        summaryStatus: _summaryStatus(c, l),
        statusChip: _statusChip(c, l),
        statusChipPregnancy: c.isPregnant,
        statusChipLate: _statusChipLate(c),
        bandNotMeasuring: c.isBandNotMeasuring,
        wearable: c.latestWearable,
        onOpenStatus: () => setState(() => _index = 1),
        weeklyDigest: computeWeeklyDigest(
          c.dayLogs, c.waterLog, c.sleepNights, DateTime.now(),
          waterGoal: c.waterGoal,
        ),
        setupProgress: computeSetupProgress(
          signedIn: c.isSignedIn,
          hasName: c.displayName.trim().isNotEmpty,
          hasHealthData: c.dueDate != null || c.periodDays.isNotEmpty,
          hasChild: c.children.isNotEmpty,
          hasZone: c.children.any((ch) => ch.geofences.isNotEmpty),
          hasDetails: c.profile.hasBirthDate && c.profile.hasCity,
          hasBackup: c.lastExportAt != null,
        ),
        // Each unfinished step lands on the screen that COMPLETES it, not a
        // catch-all Profile tab (tapping "add a child" used to open Profile).
        onOpenSetup: (step) {
          switch (step) {
            case SetupStep.signIn:
              openSignIn(context, c);
            case SetupStep.profileName:
            case SetupStep.details: // birth date + city live in the same editor
              showEditProfileSheet(context, c);
            case SetupStep.healthMode: // due date / first period → women's health
              setState(() => _index = 1);
            case SetupStep.child:
              showAddChildSheet(context, c);
            case SetupStep.zone: // safe zones are added on the child map
              setState(() => _index = 2);
            case SetupStep.backup: // export lives on the profile tab
              setState(() => _index = 3);
          }
        },
        onLogVitals: () => _logVitals(context, c),
        // Screen 05's dark card. The vitals sheet already owns the camera path;
        // this surfaces it on the screen of somebody with no band, where it is
        // the fastest way to get a blood pressure in. Null with no server, so
        // the card is not offered when it cannot work.
        onScanMonitor: c.api == null ? null : () => _logVitals(context, c),
        awaitingRepeat: c.awaitingRepeat,
        nextAppointment: nextAppointment(c.appointments, DateTime.now()),
        nowForAppointment: DateTime.now(),
        onOpenAppointments: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AppointmentsScreen(controller: c)),
        ),
        // The state antenatal protocol's due/next visit, shown beside her own
        // appointment. Only while pregnant (gestation known).
        pregnancyWeek: c.isPregnant ? c.gestation?.week : null,
        onOpenAntenatalPlan: c.gestation == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AntenatalPlanScreen(
                    week: c.gestation!.week,
                    dueDate: c.dueDate,
                    onBook: (visit, at) => c.addAppointment(
                      l.t('an_book_title', {'n': visit.number}), at),
                  ),
                )),
        onLocaleChange: c.setLocale,
        onOpenProfile: () => setState(() => _index = 3),
        onOpenAdvisor: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AdvisorScreen(
            samples: c.samples,
            lastNight: c.lastNight,
            recentNights: c.sleepNights,
            waterCount: c.waterFor(DateTime.now()),
            waterGoal: c.waterGoal,
            nowHour: DateTime.now().hour,
            // The conversational assistant, when its controller is attached
            // (a network build). Null in offline/test builds hides the entry.
            onOpenChat: c.chat == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => AssistantChatScreen(controller: c.chat!)),
                    ),
          )),
        ),
        waterCount: c.waterFor(DateTime.now()),
        waterGoal: c.waterGoal,
        timelineStage: _stageFor(c),
        timelineItems: _contentFor(c),
        onOpenContent: _openContent,
        onSeeAllContent: _stageFor(c) == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TimelineContentScreen(
                    stage: _stageFor(c)!,
                    items: _contentFor(c),
                    onOpen: _openContent,
                  ),
                )),
        // Screen 53's hero and its three quick actions. Passing the data AND
        // the handlers together: a hero wired to nothing is the defect this
        // screen already had once.
        gestation: c.gestation,
        // Screen 55: her cycle, and the three routers that let her tell the app
        // her stage changed — «Тест положительный» had no entry point at all.
        hasChild: c.children.isNotEmpty,
        // Screen 54's block. Only a child with a birth date has an age to
        // place her on the timeline, so one without falls through to the
        // cycle — the same rule the calendar follows.
        childHeroName: _heroChild(c)?.name,
        childHeroAgeMonths: _heroChild(c) == null
            ? null
            : ageInMonths(_heroChild(c)!.dateOfBirth!, DateTime.now()),
        childGrowth: _heroChild(c) == null ? const [] : c.growthFor(_heroChild(c)!.id),
        onOpenChild: () => setState(() => _index = 2),
        cycleInfo: c.cycle,
        cyclePhase: cyclePhaseFor(c.cycle),
        cycleConfidence: () {
          final reg = cycleRegularity(cycleHistory(c.periodDays));
          return predictionConfidence(
            completedCycles: reg.cyclesConsidered,
            variationDays: reg.variationDays,
          );
        }(),
        onPlanning: () => setState(() => _index = 1), // the cycle calendar
        onPregnant: () => _recordPositiveTest(context, c),
        onHasChild: () => showAddChildSheet(context, c),
        kicksToday: c.logFor(DateTime.now()).kicks,
        loggedWellbeingToday: c.logFor(DateTime.now()).mood != null,
        latestWeightKg: c.weights.isEmpty ? null : c.weights.last.kg,
        onLogKick: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => KickSessionScreen(
                  onSave: (n, elapsed) =>
                      c.logKickSession(DateTime.now(), n, elapsed)),
            )),
        onLogDay: () => showDayLogSheet(context, c, DateTime.now()),
        onLogWeight: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PregnancyWeightScreen(
                  weeklyRateKg: weeklyGainRate(c.weights)),
            )),
        onLogSleep: () => _logSleep(context, c),
        onAddWater: () => c.addWater(DateTime.now()),
        onRemoveWater: () => c.addWater(DateTime.now(), -1),
        onSetWaterGoal: c.setWaterGoal,
        onOpenWaterHistory: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WaterHistoryScreen(
            week: lastNDays(c.waterLog, DateTime.now(), 7),
            goal: c.waterGoal,
            streak: waterStreak(c.waterLog, DateTime.now(), c.waterGoal),
            controller: c, // makes past days correctable
          ),
        )),
      ),
      WomensHealthScreen(
        controller: c,
        // The same published content the dashboard shows, filtered to the
        // viewer, so the pregnancy calendar carries this week's tips instead of
        // a bare header.
        tips: _contentFor(c),
        onOpenTip: _openContent,
        onSeeAllTips: () => setState(() => _index = 0), // the dashboard hosts the full shelf
      ),
      ChildMapScreen(
        childName: c.childName,
        hasNamedChild: c.hasNamedChild,
        childLocation: loc?.coords,
        updatedAt: loc?.at,
        fences: c.geofences,
        now: DateTime.now(),
        mapBuilder: _buildMap,
        childOptions: [for (final ch in c.children) (id: ch.id, name: ch.name)],
        selectedChildId: c.selectedChild?.id,
        childAgeMonths: c.selectedChild?.hasDateOfBirth == true
            ? c.selectedChild!.ageInMonths(DateTime.now())
            : null,
        hasPairedTracker: (c.selectedChild?.tagId ?? '').isNotEmpty,
        onSelectChild: c.selectChild,
        onAddChild: () => showAddChildSheet(context, c),
        onAddDevice: () => showAddDeviceSheet(context, c),
        onManageZones: c.selectedChild == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ZonesScreen(controller: c, childId: c.selectedChild!.id),
                )),
        // UNREAD, not total. The badge counted everything that had ever
        // happened, so it never went down and stopped meaning anything —
        // which is the state a badge is worst in, because it also stops
        // meaning anything on the day something is actually wrong.
        alertCount: c.unreadAlertCount,
        onOpenAlerts: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NotificationCentreScreen(
            alerts: c.alerts,
            now: DateTime.now(),
            readUpTo: c.alertsReadUpTo,
            onReadAll: c.markAlertsRead,
            // The per-channel switches are screen 25 and do not exist yet.
            // Null hides the button rather than opening nothing.
            onConfigure: null,
            // The old alerts view, kept for what it alone does: per-child
            // counts and «сколько дней без SOS». Reached from here rather
            // than left unreferenced — deleting a working screen to tidy an
            // import is worse than either.
            onOpenStats: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AlertsScreen(controller: c)),
            ),
          ),
        )),
        batteryPct: c.selectedChildBattery,
        batteryHistory: c.selectedChildBatteryHistory,
        zoneEnteredAt: zoneEnteredAt,
        lastCheckInAt: lastCheckIn(c.alerts, c.childName),
        onCheckIn: c.selectedChild == null ? null : () => c.logChildEvent(AlertKind.checkIn),
        onSos: c.selectedChild == null ? null : () => c.logChildEvent(AlertKind.sos),
        // Screen 47. Needs a child AND a server — the trail lives only on the
        // server, so offline the button is absent rather than opening a screen
        // that can never load.
        onDayHistory: (c.selectedChild == null || c.api == null)
            ? null
            : () => _openDayHistory(context, c),
        // Screen 20. The strip at the top of the shell says the app is
        // offline; this is what the MAP does about it, which is the screen
        // where being wrong about staleness costs something.
        isOffline: c.isOffline,
        onRefresh: c.api == null ? null : () => c.refreshChildLocation(),
      ),
      ProfileScreen(
        controller: c,
        // Both summary tiles lead to the family hub (Child tab), where children
        // and trackers are actually managed — previously they were dead cards.
        onOpenChildren: () => setState(() => _index = 2),
        onOpenDevices: () => setState(() => _index = 2),
        // Screen 40. The grants live on the server; without one the row is
        // absent rather than opening a screen that can only fail.
        onOpenFamilyAccess:
            c.api == null ? null : () => _openFamilyAccess(context, c),
        // Screen 42. The orders live on the server, matched on her phone.
        onOpenMyOrder: c.api == null ? null : () => _openMyOrder(context, c),
        // Screen 41. Always available — the offer does not need a server, and
        // the WhatsApp number is fetched when the screen opens.
        onOpenShop: () => _openShop(context, c),
      ),
    ];

    return Scaffold(
      body: Column(
        children: [
          // A quiet offline strip across the top of the app — so a stale reading
          // or a not-yet-synced entry reads as "waiting for the network", not as
          // broken. Driven by the connectivity service wired in main.dart.
          if (c.isOffline)
            Material(
              color: Palette.amber.withValues(alpha: 0.16),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.wifi_off_rounded, size: 15, color: Palette.amber),
                    const SizedBox(width: 8),
                    Text(l.t('offline_banner'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Palette.text)),
                  ]),
                ),
              ),
            ),
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
      bottomNavigationBar: DsTabBarSurface(
        child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.favorite_outline),
              selectedIcon: const Icon(Icons.favorite),
              label: l.t('nav_today')),
          NavigationDestination(
              icon: const Icon(Icons.calendar_today_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
              label: l.t('nav_calendar')),
          NavigationDestination(
              icon: const Icon(Icons.location_on_outlined),
              selectedIcon: const Icon(Icons.location_on),
              label: l.t('nav_child')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l.t('nav_profile')),
        ],
        ),
      ),
    );
  }

  /// A one-line pregnancy/cycle status for the shared health summary (empty when
  /// there's nothing to say).
  String _summaryStatus(AppController c, L10n l) {
    if (c.isPregnant) {
      final g = c.gestation;
      if (g != null) return l.t('share_status_pregnancy', {'week': g.week});
      return '';
    }
    final cyc = c.cycle;
    if (cyc.hasData && cyc.cycleDay != null) {
      final until = cyc.daysUntilNextPeriod ?? 0;
      return until >= 0
          ? l.t('share_status_cycle', {'day': cyc.cycleDay, 'n': until})
          : l.t('share_status_cycle_late', {'day': cyc.cycleDay, 'n': -until});
    }
    return '';
  }

/// Screen 41 — «Магазин».
  ///
  /// The whole offer inside the app. Until now the only way to buy anything was
  /// the landing page in a browser, which a customer who already has the app is
  /// unlikely to be looking at.
  void _openShop(BuildContext context, AppController c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ShopRoute(controller: c),
    ));
  }

  /// Screen 42 — «Мой заказ».
  ///
  /// «Написать» opens WhatsApp on the number the admin panel configured. It is
  /// fetched rather than compiled in, and the button is absent when there is
  /// none — a contact button that opens nothing is worse than no button on the
  /// screen somebody reaches when a delivery has gone wrong.
  void _openMyOrder(BuildContext context, AppController c) {
    final api = c.api;
    if (api == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MyOrderRoute(controller: c),
    ));
  }

  /// Screen 40 — «Семейный доступ».
  ///
  /// Every callback reports what the SERVER answered. A remove that returns
  /// true on a failed request would leave a mother believing she had shut
  /// somebody out of her child's location when she had not.
  void _openFamilyAccess(BuildContext context, AppController c) {
    final api = c.api;
    if (api == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FamilyAccessScreen(
        now: DateTime.now(),
        load: () async => FamilyAccess.fromJson(await api.familyAccess()),
        onInvite: (level, label) async {
          try {
            final r = await api.createFamilyInvite(level: level.wire, label: label);
            final token = r['token'];
            return token is String && token.isNotEmpty ? token : null;
          } catch (_) {
            // Null, so the screen says the link could not be made. Silence
            // here leaves her waiting for one that was never created.
            return null;
          }
        },
        onRemove: (m) => api.removeFamilyMember(m.memberUserId),
        onRevoke: (i) => api.revokeFamilyInvite(i.tokenHash),
        // The other side of the invitation. Without it a relative who was sent
        // a link has nowhere to put the code and the path dead-ends.
        onAccept: (token) async {
          try {
            return await api.acceptFamilyInvite(token);
          } catch (_) {
            return (ok: false, reason: null);
          }
        },
        // The link somebody actually receives. A path on the site rather than
        // a custom scheme, so it opens for a relative who has not installed
        // the app yet — which is most of them, the first time.
        linkFor: (token) => 'https://ana-bala.kz/join/$token',
      ),
    ));
  }

  /// Screen 47 — «История дня» for the selected child.
  ///
  /// The loader THROWS on failure rather than returning null: the screen shows
  /// a failed load differently from an empty day, and it cannot tell the two
  /// apart from a null.
  void _openDayHistory(BuildContext context, AppController c) {
    final api = c.api;
    final child = c.selectedChild;
    if (api == null || child == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DayHistoryScreen(
        childName: c.childName,
        now: DateTime.now(),
        load: (day) async => DayHistory.fromJson(await api.childDay(child.id, day)),
        routeMapBuilder: _buildRouteMap,
        onSaveOutcome: (event, outcome) =>
            api.saveSosOutcome(child.id, event.at, outcome.wire),
      ),
    ));
  }

  /// Open the hand-entry sheet and record whatever comes back. The controller
  /// triages it exactly as it would a band reading, so this may raise the
  /// emergency screen — which is the intended behaviour.
  Future<void> _logVitals(BuildContext context, AppController c) async {
    final api = c.api;
    final reading = await showLogVitalsSheet(
      context,
      // Only offer the photo shortcut when we can reach the server; offline, the
      // sheet is manual-entry only.
      onScan: api == null ? null : (bytes, mediaType) => api.extractVitalsFromImage(bytes, mediaType),
    );
    if (reading == null) return;
    final saved = c.logManualVitals(reading);
    if (!saved || !context.mounted) return;
    final l = L10nScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('vitals_saved')), behavior: SnackBarBehavior.floating),
    );
  }

  /// Where this family is on the timeline: their pregnancy week if there is a
  /// due date, otherwise the selected child's age in months.
  TimelineStage? _stageFor(AppController c) => currentStage(
        gestationWeek: c.isPregnant ? c.gestation?.week : null,
        childAgeMonths: c.selectedChild?.hasDateOfBirth == true
            ? c.selectedChild!.ageInMonths(DateTime.now())
            : null,
      );

  /// This stage's shelf, narrowed to what actually applies to her.
  ///
  /// City and birth date are optional, and a profile without them loses nothing
  /// from the baseline — it only misses the extras that depend on knowing, like
  /// a product that ships to one city.
  List<ContentItem> _contentFor(AppController c) {
    final stage = _stageFor(c);
    if (stage == null) return const [];
    final p = c.profile;
    return itemsForViewer(
      widget.catalog.itemsFor(stage),
      ContentViewer(city: p.city, ageYears: p.ageYears(DateTime.now())),
    );
  }

  /// Open a lesson video or a product page in the browser. Items without a URL
  /// are not tappable, so this is only reached for a real link.
  Future<void> _openContent(ContentItem item) async {
    // A lesson we host plays in OUR player, with our controls and no third
    // party's branding. Everything else — a shop page, a YouTube link — leaves
    // the app, which for YouTube is not a limitation but a requirement.
    if (item.playsInApp) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LessonPlayerScreen(item: item)),
      );
      return;
    }
    final target = item.video?.url ?? item.url;
    final uri = Uri.tryParse(target);
    if (uri == null || target.trim().isEmpty) return;

    // Attempt it and report the result, rather than asking permission first.
    //
    // canLaunchUrl answers "is a handler visible to me", which on Android 11+
    // means "did the manifest declare a <queries> intent for this scheme" —
    // and it did not for https. So this returned false on every modern Android
    // device and the tap did nothing: no browser, no error, no explanation.
    // The manifest is fixed, but gating on that check would leave the same
    // dead-tap failure mode one packaging mistake away.
    final l = L10nScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.t('link_open_failed')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// The child the home block is about: the selected one when it has a birth
  /// date, otherwise the first that does. Null when none has one — there is no
  /// age to count from, and guessing is worse than falling through.
  ChildProfile? _heroChild(AppController c) {
    final sel = c.selectedChild;
    if (sel?.dateOfBirth != null) return sel;
    for (final ch in c.children) {
      if (ch.dateOfBirth != null) return ch;
    }
    return null;
  }

  /// «Тест положительный» — she tells the app she is pregnant.
  ///
  /// The design system asks for stage changes to happen as EVENTS rather than
  /// through a date picker, and this one had no entry point anywhere: the only
  /// way to become pregnant in this app was to find «срок родов» in the
  /// calendar and set a date.
  ///
  /// It still needs a due date — every pregnancy calculation is anchored to one
  /// — so it asks for the last period instead, which is the date she actually
  /// knows, and derives the rest. Nothing is saved until she picks.
  Future<void> _recordPositiveTest(BuildContext context, AppController c) async {
    final l = L10nScope.of(context);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: l.t('preg_lmp_help'),
      initialDate: c.cycle.lastPeriodStart ?? now.subtract(const Duration(days: 42)),
      // A pregnancy runs 40 weeks from the last period; anything older than
      // that is not a start date, and a future one is a mis-set picker.
      firstDate: now.subtract(const Duration(days: 280)),
      lastDate: now,
    );
    if (picked == null || !context.mounted) return;

    // 280 days from the last period is the standard estimate — the same
    // arithmetic gestationFor already runs in reverse.
    c.setDueDate(picked.add(const Duration(days: 280)));
    if (!context.mounted) return;
    // Land her on the calendar, which is now the pregnancy one: the change is
    // large enough that showing it beats announcing it.
    setState(() => _index = 1);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.t('preg_started'))));
  }

  /// Open the sleep sheet and record the night. Unlike band summaries this is
  /// persisted, so it survives a restart — nothing else would re-supply it.
  Future<void> _logSleep(BuildContext context, AppController c) async {
    final entry = await showLogSleepSheet(context, now: DateTime.now());
    if (entry == null) return;
    final saved = c.logManualSleep(entry);
    if (!saved || !context.mounted) return;
    final l = L10nScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('sleep_logged')), behavior: SnackBarBehavior.floating),
    );
  }

  /// A short chip label for the dashboard: pregnancy week or cycle day. Empty
  /// when there's no cycle/pregnancy data yet (chip hidden).
  String _statusChip(AppController c, L10n l) {
    if (c.isPregnant) {
      final g = c.gestation;
      return g != null ? l.t('db_chip_pregnancy', {'n': g.week}) : '';
    }
    final cyc = c.cycle;
    if (!cyc.hasData || cyc.cycleDay == null) return '';
    // A late period is the thing most worth surfacing — say so instead of
    // burying it behind a cycle-day number.
    final until = cyc.daysUntilNextPeriod;
    if (cyc.isPredictedLate && until != null) return l.t('db_chip_late', {'n': -until});
    return l.t('db_chip_cycle', {'n': cyc.cycleDay});
  }

  /// Whether the cycle chip should read as "worth a look" (amber) rather than
  /// routine. Pregnancy is never late.
  bool _statusChipLate(AppController c) => !c.isPregnant && c.cycle.isPredictedLate;

  /// Real Google map with the child marker + geofence circles — or a graceful
  /// placeholder when Maps isn't configured (avoids a black platform-view surface).
  Widget _buildMap(BuildContext context, Coordinates? child, List<Geofence> fences) {
    if (!_mapsEnabled) return _MapPlaceholder(fences: fences, child: child);
    final center = child ??
        (fences.isNotEmpty && fences.first.center != null
            ? fences.first.center!
            : const Coordinates(43.238949, 76.889709));
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: LatLng(center.lat, center.lng), zoom: 15),
      myLocationButtonEnabled: false,
      circles: {
        for (final f in fences)
          if (f.shape == GeofenceShape.circle && f.center != null)
            Circle(
              circleId: CircleId(f.id),
              center: LatLng(f.center!.lat, f.center!.lng),
              radius: f.radiusM ?? 0,
              strokeWidth: 2,
              strokeColor: Palette.violet,
              fillColor: Palette.violet.withValues(alpha: 0.13),
            ),
      },
      markers: {
        if (child != null)
          Marker(markerId: const MarkerId('child'), position: LatLng(child.lat, child.lng)),
      },
    );
  }
}

/// Screen 41, with its WhatsApp number resolved before the screen is built.
///
/// Same reason as screen 42: the number decides whether the buy BUTTONS exist,
/// and a shop that grows its buy buttons a second after opening is one somebody
/// taps by accident.
class _ShopRoute extends StatefulWidget {
  final AppController controller;
  const _ShopRoute({required this.controller});

  @override
  State<_ShopRoute> createState() => _ShopRouteState();
}

class _ShopRouteState extends State<_ShopRoute> {
  String _whatsapp = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contact = await widget.controller.api?.getShopContact();
    if (!mounted) return;
    setState(() {
      _whatsapp = contact?.whatsapp ?? '';
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = widget.controller;
    final digits = _whatsapp.replaceAll(RegExp(r'\D'), '');
    final now = DateTime.now();
    return ShopScreen(
      pregnant: c.isPregnant,
      childAgesMonths: [
        for (final ch in c.children)
          if (ch.hasDateOfBirth) ch.ageInMonths(now),
      ],
      onOrder: digits.isEmpty
          ? null
          : (message) => launchUrl(
                Uri.parse(
                    'https://wa.me/$digits?text=${Uri.encodeComponent(message)}'),
                mode: LaunchMode.externalApplication,
              ),
    );
  }
}

/// Screen 42, with its WhatsApp number resolved before the screen is built.
///
/// A small stateful wrapper rather than a FutureBuilder inside the screen: the
/// number decides whether a BUTTON exists, and a screen that grows a contact
/// button a second after it opens is one somebody taps by accident.
class _MyOrderRoute extends StatefulWidget {
  final AppController controller;
  const _MyOrderRoute({required this.controller});

  @override
  State<_MyOrderRoute> createState() => _MyOrderRouteState();
}

class _MyOrderRouteState extends State<_MyOrderRoute> {
  String _whatsapp = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contact = await widget.controller.api?.getShopContact();
    if (!mounted) return;
    setState(() {
      _whatsapp = contact?.whatsapp ?? '';
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.controller.api;
    if (!_ready || api == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final digits = _whatsapp.replaceAll(RegExp(r'\D'), '');
    return MyOrderScreen(
      load: () async => MyOrders.fromJson(await api.myOrders()),
      onCancel: (o) => api.cancelMyOrder(o.orderId),
      onWrite: digits.isEmpty
          ? null
          : () => launchUrl(
                Uri.parse('https://wa.me/$digits'),
                mode: LaunchMode.externalApplication,
              ),
      // The only fix for a missing number is the profile editor.
      onAddPhone: () {
        Navigator.of(context).pop();
        showEditProfileSheet(context, widget.controller);
      },
    );
  }
}

/// The day's route, for screen 47.
///
/// A polyline through the thinned points with a dot at each, and a distinct
/// marker where an SOS was pressed. Camera on the first point rather than on
/// the child's current position: this screen is about where she WAS.
Widget _buildRouteMap(
  BuildContext context,
  List<RoutePoint> points,
  List<DayEvent> events,
) {
  if (!_mapsEnabled) {
    return const _MapPlaceholder(fences: [], child: null);
  }
  // The first point of the day; failing that, an event that carries a
  // position (screen 48 opens with no trail at all, only the SOS); failing
  // that, Almaty, the same fallback the live map uses.
  final located = events.where((e) => e.lat != null && e.lng != null);
  final anchor = points.isNotEmpty
      ? LatLng(points.first.lat, points.first.lng)
      : located.isNotEmpty
          ? LatLng(located.first.lat!, located.first.lng!)
          : const LatLng(43.238949, 76.889709);
  return GoogleMap(
    initialCameraPosition: CameraPosition(target: anchor, zoom: 14),
    myLocationButtonEnabled: false,
    polylines: {
      if (points.length >= 2)
        Polyline(
          polylineId: const PolylineId('route'),
          width: 4,
          color: Palette.violet,
          points: [for (final p in points) LatLng(p.lat, p.lng)],
        ),
    },
    markers: {
      for (final (i, p) in points.indexed)
        Marker(
          markerId: MarkerId('p$i'),
          position: LatLng(p.lat, p.lng),
          // Only the ends are labelled. A tooltip on every one of forty points
          // is a map you cannot tap through.
          infoWindow: i == 0 || i == points.length - 1
              ? InfoWindow(title: '${p.at.hour}:${p.at.minute.toString().padLeft(2, '0')}')
              : InfoWindow.noText,
        ),
      for (final (i, e) in events.indexed)
        if (e.kind == DayEventKind.sos && e.lat != null && e.lng != null)
          Marker(
            markerId: MarkerId('sos$i'),
            position: LatLng(e.lat!, e.lng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
    },
  );
}

/// Shown in place of GoogleMap when no Maps key is configured. Just a calm
/// message — the child's zones are surfaced by the floating zone pills layered
/// above the map, and live position by the status card, so we don't repeat them
/// here.
class _MapPlaceholder extends StatelessWidget {
  final List<Geofence> fences;
  final Coordinates? child;
  const _MapPlaceholder({required this.fences, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = L10nScope.of(context);
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 56, color: scheme.primary),
          const SizedBox(height: 12),
          Text(l.t('map_unavailable'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
        ],
      ),
    );
  }
}
