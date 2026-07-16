/// Map-based safe-zone picker: tap the map to set the zone centre and drag the
/// radius slider to size the circle. Returns the chosen centre + radius.
/// Requires a Google Maps key (build with --dart-define=MAPS_ENABLED=true); the
/// zone sheet only offers this when maps are enabled, and keeps the
/// "use my current location" method as the no-key fallback.
library;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/geofence.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

typedef ZonePick = ({Coordinates center, double radius});

class MapZonePickerScreen extends StatefulWidget {
  final Coordinates initialCenter;
  final double initialRadius;
  const MapZonePickerScreen({super.key, required this.initialCenter, required this.initialRadius});

  @override
  State<MapZonePickerScreen> createState() => _MapZonePickerScreenState();
}

class _MapZonePickerScreenState extends State<MapZonePickerScreen> {
  late LatLng _center;
  late double _radius;

  @override
  void initState() {
    super.initState();
    _center = LatLng(widget.initialCenter.lat, widget.initialCenter.lng);
    _radius = widget.initialRadius;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('zone_pick_on_map'))),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _center, zoom: 15),
              myLocationButtonEnabled: false,
              onTap: (pos) => setState(() => _center = pos),
              circles: {
                Circle(
                  circleId: const CircleId('zone'),
                  center: _center,
                  radius: _radius,
                  strokeWidth: 2,
                  strokeColor: Palette.violet,
                  fillColor: Palette.violet.withValues(alpha: 0.18),
                ),
              },
              markers: {Marker(markerId: const MarkerId('center'), position: _center)},
            ),
          ),
          // Hint chip
          Positioned(
            top: 12, left: 12, right: 12,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Palette.bgElevated,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4), spreadRadius: -4)],
                ),
                child: Row(children: [
                  const Icon(Icons.touch_app_outlined, size: 18, color: Palette.violet),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l.t('zone_pick_hint'), style: const TextStyle(fontSize: 13))),
                ]),
              ),
            ),
          ),
          // Radius + save panel
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: BoxDecoration(
                  color: Palette.bgElevated,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10), spreadRadius: -6)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Text(l.t('zone_radius'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(l.t('zone_meters', {'m': _radius.round()}),
                          style: const TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: Palette.violet)),
                    ]),
                    Slider(
                      value: _radius,
                      min: 50, max: 500, divisions: 45,
                      activeColor: Palette.violet,
                      onChanged: (v) => setState(() => _radius = v),
                    ),
                    const SizedBox(height: 4),
                    FilledButton(
                      onPressed: () => Navigator.pop<ZonePick>(
                        context,
                        (center: Coordinates(_center.latitude, _center.longitude), radius: _radius),
                      ),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: Text(l.t('act_save')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
