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
import 'theme.dart';
import 'appointments/appointments_screen.dart';
import 'calendar/antenatal_plan_screen.dart';
import 'calendar/womens_health_screen.dart';
import 'dashboard/health_dashboard_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/timeline_content.dart';
import 'content/lesson_player_screen.dart';
import 'content/timeline_content_screen.dart';
import 'dashboard/log_sleep_sheet.dart';
import 'dashboard/log_vitals_sheet.dart';
import 'dashboard/water_history_screen.dart';
import 'profile/profile_screen.dart';
import 'tracking/alerts_screen.dart';
import 'tracking/child_map_screen.dart';
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
          hasName: c.displayName.trim().isNotEmpty,
          hasHealthData: c.dueDate != null || c.periodDays.isNotEmpty,
          hasChild: c.children.isNotEmpty,
          hasZone: c.children.any((ch) => ch.geofences.isNotEmpty),
          hasDetails: c.profile.hasBirthDate && c.profile.hasCity,
          hasBackup: c.lastExportAt != null,
        ),
        onOpenSetup: () => setState(() => _index = 3), // profile / settings tab
        onLogVitals: () => _logVitals(context, c),
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
                  builder: (_) => AntenatalPlanScreen(week: c.gestation!.week),
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
        alertCount: c.alerts.length,
        onOpenAlerts: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlertsScreen(controller: c)),
        ),
        batteryPct: c.selectedChildBattery,
        batteryHistory: c.selectedChildBatteryHistory,
        zoneEnteredAt: zoneEnteredAt,
        lastCheckInAt: lastCheckIn(c.alerts, c.childName),
        onCheckIn: c.selectedChild == null ? null : () => c.logChildEvent(AlertKind.checkIn),
        onSos: c.selectedChild == null ? null : () => c.logChildEvent(AlertKind.sos),
      ),
      ProfileScreen(controller: c),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.favorite_outline),
              selectedIcon: const Icon(Icons.favorite),
              label: l.t('nav_health')),
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

  /// Open the hand-entry sheet and record whatever comes back. The controller
  /// triages it exactly as it would a band reading, so this may raise the
  /// emergency screen — which is the intended behaviour.
  Future<void> _logVitals(BuildContext context, AppController c) async {
    final reading = await showLogVitalsSheet(context);
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
              strokeColor: const Color(0xFF8E5BA6),
              fillColor: const Color(0x228E5BA6),
            ),
      },
      markers: {
        if (child != null)
          Marker(markerId: const MarkerId('child'), position: LatLng(child.lat, child.lng)),
      },
    );
  }
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
