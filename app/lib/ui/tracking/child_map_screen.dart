/// Child tracking screen — live map with geofence zones, the child's marker, and
/// a status card driven by the verified deriveChildStatus() logic + L10n.
///
/// The map (google_maps_flutter) is a platform view that can't render in a pure
/// widget test, so it's isolated behind [mapBuilder] — the default builds the real
/// GoogleMap; tests inject a stub. The status card is plain widgets and IS testable.
library;

import 'package:flutter/material.dart';
import '../../core/geofence.dart';
import '../../domain/child_tracker_state.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

typedef MapBuilder = Widget Function(
    BuildContext context, Coordinates? child, List<Geofence> fences);

typedef ChildOption = ({String id, String name});

class ChildMapScreen extends StatelessWidget {
  final String childName;
  final Coordinates? childLocation;
  final DateTime? updatedAt;
  final List<Geofence> fences;
  final DateTime now;
  final MapBuilder mapBuilder;

  // Family management (optional — omitted in widget tests).
  final List<ChildOption> childOptions;
  final String? selectedChildId;
  final void Function(String id)? onSelectChild;
  final VoidCallback? onAddChild;
  final VoidCallback? onAddDevice;

  const ChildMapScreen({
    super.key,
    required this.childName,
    required this.childLocation,
    required this.updatedAt,
    required this.fences,
    required this.now,
    required this.mapBuilder,
    this.childOptions = const [],
    this.selectedChildId,
    this.onSelectChild,
    this.onAddChild,
    this.onAddDevice,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final status = deriveChildStatus(
      childName: childName,
      location: childLocation,
      updatedAt: updatedAt,
      fences: fences,
      now: now,
    );

    return AuroraBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(l.t('tr_title', {'name': childName})),
        actions: [
          if (onAddChild != null || onAddDevice != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.add, color: Palette.text),
              color: Palette.surfaceHi,
              onSelected: (v) {
                if (v == 'child') onAddChild?.call();
                if (v == 'device') onAddDevice?.call();
              },
              itemBuilder: (_) => [
                if (onAddChild != null)
                  PopupMenuItem(value: 'child', child: Row(children: [
                    const Icon(Icons.child_care, size: 18, color: Palette.textDim),
                    const SizedBox(width: 10), Text(l.t('tr_add_child')),
                  ])),
                if (onAddDevice != null)
                  PopupMenuItem(value: 'device', child: Row(children: [
                    const Icon(Icons.watch, size: 18, color: Palette.textDim),
                    const SizedBox(width: 10), Text(l.t('tr_add_device')),
                  ])),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (childOptions.length > 1 || (childOptions.isNotEmpty && onAddChild != null))
            _ChildSelector(
              options: childOptions,
              selectedId: selectedChildId,
              onSelect: onSelectChild,
            ),
          Expanded(child: mapBuilder(context, childLocation, fences)),
          _StatusCard(status: status, headline: l.trackingHeadline(status, childName, now), l: l),
        ],
      ),
      ),
    );
  }
}

class _ChildSelector extends StatelessWidget {
  final List<ChildOption> options;
  final String? selectedId;
  final void Function(String id)? onSelect;
  const _ChildSelector({required this.options, required this.selectedId, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(o.name),
                selected: o.id == selectedId,
                onSelected: (_) => onSelect?.call(o.id),
                selectedColor: Palette.violet.withValues(alpha: 0.25),
                backgroundColor: Palette.glass,
                side: const BorderSide(color: Palette.border),
                labelStyle: TextStyle(
                  color: o.id == selectedId ? Palette.text : Palette.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ChildStatus status;
  final String headline;
  final L10n l;
  const _StatusCard({required this.status, required this.headline, required this.l});

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
                _FreshnessPill(status.freshness, l),
                const Spacer(),
                if (status.distanceFromHomeM != null)
                  Text(l.distanceFromHome(status.distanceFromHomeM!),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(headline, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (status.currentZone != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.place_outlined, size: 16),
                const SizedBox(width: 4),
                Text(l.t('tr_inside_zone', {'zone': status.currentZone}),
                    style: TextStyle(color: Colors.grey.shade700)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _FreshnessPill extends StatelessWidget {
  final Freshness freshness;
  final L10n l;
  const _FreshnessPill(this.freshness, this.l);

  @override
  Widget build(BuildContext context) {
    final color = switch (freshness) {
      Freshness.live => const Color(0xFF12B886),
      Freshness.recent => const Color(0xFFFAB005),
      Freshness.stale => const Color(0xFF868E96),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(l.freshnessLabel(freshness),
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}
