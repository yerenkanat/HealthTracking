/// Home shell — bottom-nav container for the two primary journeys:
/// the mother's health dashboard and the child's tracking map. Rebuilds on
/// AppController changes via its `changes` stream.
library;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../app/app_controller.dart';
import '../core/geofence.dart';
import '../l10n/l10n_scope.dart';
import 'chat/assistant_chat_screen.dart';
import 'dashboard/health_dashboard_screen.dart';
import 'tracking/child_map_screen.dart';

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
    final chat = c.chat;

    final pages = [
      HealthDashboardScreen(
        samples: c.samples,
        greetingName: '',
        currentLocale: c.locale,
        onLocaleChange: c.setLocale,
      ),
      chat != null
          ? AssistantChatScreen(controller: chat)
          : const Center(child: CircularProgressIndicator()),
      ChildMapScreen(
        childName: c.childName,
        childLocation: loc?.coords,
        updatedAt: loc?.at,
        fences: c.geofences,
        now: DateTime.now(),
        mapBuilder: _buildMap,
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
              icon: const Icon(Icons.spa_outlined),
              selectedIcon: const Icon(Icons.spa),
              label: l.t('nav_assistant')),
          NavigationDestination(
              icon: const Icon(Icons.location_on_outlined),
              selectedIcon: const Icon(Icons.location_on),
              label: l.t('nav_child')),
        ],
      ),
    );
  }

  /// Real Google map with the child marker + geofence circles.
  Widget _buildMap(BuildContext context, Coordinates? child, List<Geofence> fences) {
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
