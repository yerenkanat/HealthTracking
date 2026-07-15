/// Child tracking screen — live map with geofence zones, the child's marker, and
/// a status card driven by the verified deriveChildStatus() logic.
///
/// The map itself (google_maps_flutter) is a platform view that can't render in a
/// pure widget test, so it's isolated behind [mapBuilder] — the default builds the
/// real GoogleMap; tests inject a stub. Everything above the map (the status card,
/// freshness pill, distance) is plain widgets and IS testable.
library;

import 'package:flutter/material.dart';
import '../../core/geofence.dart';
import '../../domain/child_tracker_state.dart';

typedef MapBuilder = Widget Function(
    BuildContext context, Coordinates? child, List<Geofence> fences);

class ChildMapScreen extends StatelessWidget {
  final String childName;
  final Coordinates? childLocation;
  final DateTime? updatedAt;
  final List<Geofence> fences;
  final DateTime now;
  final MapBuilder mapBuilder;

  const ChildMapScreen({
    super.key,
    required this.childName,
    required this.childLocation,
    required this.updatedAt,
    required this.fences,
    required this.now,
    required this.mapBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final status = deriveChildStatus(
      childName: childName,
      location: childLocation,
      updatedAt: updatedAt,
      fences: fences,
      now: now,
    );

    return Scaffold(
      appBar: AppBar(title: Text('Where is $childName?')),
      body: Column(
        children: [
          Expanded(child: mapBuilder(context, childLocation, fences)),
          _StatusCard(status: status),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ChildStatus status;
  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _FreshnessPill(status.freshness),
                const Spacer(),
                if (status.distanceFromHomeM != null)
                  Text(_distance(status.distanceFromHomeM!),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(status.headline,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (status.currentZone != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.place_outlined, size: 16),
                const SizedBox(width: 4),
                Text('Inside ${status.currentZone} zone',
                    style: TextStyle(color: Colors.grey.shade700)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  String _distance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km from home' : '${m.round()} m from home';
}

class _FreshnessPill extends StatelessWidget {
  final Freshness freshness;
  const _FreshnessPill(this.freshness);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (freshness) {
      Freshness.live => ('Live', const Color(0xFF12B886)),
      Freshness.recent => ('Recent', const Color(0xFFFAB005)),
      Freshness.stale => ('Delayed', const Color(0xFF868E96)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}
