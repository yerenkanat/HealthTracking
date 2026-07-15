/// Home shell — bottom-nav container for the two primary journeys:
/// the mother's health dashboard and the child's tracking map. Rebuilds on
/// AppController changes via its `changes` stream.
library;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../app/app_controller.dart';
import '../core/geofence.dart';
import '../l10n/l10n_scope.dart';
import 'advisor/advisor_screen.dart';
import 'dashboard/health_dashboard_screen.dart';
import 'settings/settings_screen.dart';
import 'tracking/child_map_screen.dart';
import 'tracking/family_sheets.dart';

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

    final l = L10nScope.of(context);

    final pages = [
      HealthDashboardScreen(
        samples: c.samples,
        greetingName: '',
        currentLocale: c.locale,
        onLocaleChange: c.setLocale,
        onOpenSettings: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SettingsScreen(controller: c)),
        ),
      ),
      AdvisorScreen(samples: c.samples),
      ChildMapScreen(
        childName: c.childName,
        childLocation: loc?.coords,
        updatedAt: loc?.at,
        fences: c.geofences,
        now: DateTime.now(),
        mapBuilder: _buildMap,
        childOptions: [for (final ch in c.children) (id: ch.id, name: ch.name)],
        selectedChildId: c.selectedChild?.id,
        onSelectChild: c.selectChild,
        onAddChild: () => showAddChildSheet(context, c),
        onAddDevice: () => showAddDeviceSheet(context, c),
      ),
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
              icon: const Icon(Icons.auto_awesome_outlined),
              selectedIcon: const Icon(Icons.auto_awesome),
              label: l.t('nav_advisor')),
          NavigationDestination(
              icon: const Icon(Icons.location_on_outlined),
              selectedIcon: const Icon(Icons.location_on),
              label: l.t('nav_child')),
        ],
      ),
    );
  }

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

/// Shown in place of GoogleMap when no Maps key is configured. Lists the child's
/// zones so the tab is still useful; the status card below shows live position.
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
          if (fences.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final f in fences)
                  Chip(
                    avatar: Icon(Icons.place, size: 16, color: scheme.primary),
                    label: Text(f.name),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
