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
import 'appointments/appointments_screen.dart';
import 'calendar/womens_health_screen.dart';
import 'dashboard/health_dashboard_screen.dart';
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
  const HomeShell({super.key, required this.controller});

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
          hasBackup: c.lastExportAt != null,
        ),
        onOpenSetup: () => setState(() => _index = 3), // profile / settings tab
        nextAppointment: nextAppointment(c.appointments, DateTime.now()),
        nowForAppointment: DateTime.now(),
        onOpenAppointments: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AppointmentsScreen(controller: c)),
        ),
        onLocaleChange: c.setLocale,
        onOpenProfile: () => setState(() => _index = 3),
        onOpenAdvisor: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AdvisorScreen(
            samples: c.samples,
            lastNight: c.lastNight,
            waterCount: c.waterFor(DateTime.now()),
            waterGoal: c.waterGoal,
            nowHour: DateTime.now().hour,
          )),
        ),
        waterCount: c.waterFor(DateTime.now()),
        waterGoal: c.waterGoal,
        onAddWater: () => c.addWater(DateTime.now()),
        onRemoveWater: () => c.addWater(DateTime.now(), -1),
        onSetWaterGoal: c.setWaterGoal,
        onOpenWaterHistory: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WaterHistoryScreen(
            week: lastNDays(c.waterLog, DateTime.now(), 7),
            goal: c.waterGoal,
            streak: waterStreak(c.waterLog, DateTime.now(), c.waterGoal),
          ),
        )),
      ),
      WomensHealthScreen(controller: c),
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
      body: IndexedStack(index: _index, children: pages),
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
