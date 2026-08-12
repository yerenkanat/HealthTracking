/// The live child map, and what stands in for it when there is no Maps key.
///
/// Lifted out of `home_shell.dart`, where it was a private method and a private
/// widget, the moment a SECOND screen needed it: screen 21's location card. A
/// copy of the marker/circle setup on the SOS screen would be a second answer
/// to "what does the child's position look like", and the two would drift.
///
/// google_maps_flutter is a platform view that cannot render in a widget test,
/// which is why every screen that shows a map takes a [MapBuilder] and this
/// function is what production passes in.
library;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/geofence.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

/// Google Maps needs a real API key to render. Build with
/// `--dart-define=MAPS_ENABLED=true` once android/app has a valid key; otherwise
/// every map surface shows a clean placeholder instead of a black rectangle.
const bool kMapsEnabled = bool.fromEnvironment('MAPS_ENABLED', defaultValue: false);

/// The child's position and their safe zones. Matches the [MapBuilder]
/// signature so it can be handed straight to any screen that shows a map.
Widget buildTrackingMap(
  BuildContext context,
  Coordinates? child,
  List<Geofence> fences,
) {
  if (!kMapsEnabled) return MapPlaceholder(fences: fences, child: child);
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

/// Shown in place of GoogleMap when no Maps key is configured. Just a calm
/// message — the child's zones are surfaced by the floating zone pills layered
/// above the map, and live position by the status card, so we don't repeat them
/// here.
class MapPlaceholder extends StatelessWidget {
  final List<Geofence> fences;
  final Coordinates? child;
  const MapPlaceholder({super.key, required this.fences, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = L10nScope.of(context);
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      // The caption is dropped where there is no room for it — screen 21's
      // location card is 116dp tall, and at 130% type the icon alone fills it.
      // A striped rectangle with the label cut in half is worse than the icon.
      child: LayoutBuilder(
        builder: (context, box) {
          final tight = box.maxHeight < 140;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: tight ? 32 : 56, color: scheme.primary),
              if (!tight) ...[
                const SizedBox(height: 12),
                Text(l.t('map_unavailable'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
              ],
            ],
          );
        },
      ),
    );
  }
}
