/// Child tracking screen — a full-bleed live map with neatly floating interface
/// layers above it: a child selector, geofence zone pills that light up when the
/// child is inside them, and a polished, low-anxiety status card
/// ([MinimalTrackingStatusBar]) driven by the verified deriveChildStatus() logic.
///
/// The map (google_maps_flutter) is a platform view that can't render in a pure
/// widget test, so it's isolated behind [mapBuilder] — the default builds the real
/// GoogleMap; tests inject a stub. Everything floating on top is plain widgets and
/// IS testable.
library;

import 'package:flutter/material.dart';
import '../../core/geofence.dart';
import '../../domain/child_tracker_state.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import 'child_safety_screen.dart';

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
  final int? childAgeMonths; // for age-appropriate safety tips (null if no DOB)

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
    this.childAgeMonths,
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
    final showSelector = childOptions.length > 1 || (childOptions.isNotEmpty && onAddChild != null);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _FloatingTitle(l.t('tr_title', {'name': childName})),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _FloatingIconButton(
              icon: Icons.shield_outlined,
              tooltip: l.t('safety_title'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChildSafetyScreen(
                  childName: childName,
                  ageMonths: childAgeMonths,
                  currentZone: status.currentZone,
                  freshness: status.freshness,
                  hasLocation: childLocation != null,
                ),
              )),
            ),
          ),
          if (onAddChild != null || onAddDevice != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FloatingActionChip(
                icon: Icons.add,
                onSelected: (v) {
                  if (v == 'child') onAddChild?.call();
                  if (v == 'device') onAddDevice?.call();
                },
                items: [
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
            ),
        ],
      ),
      body: Stack(
        children: [
          // Full-bleed map surface.
          Positioned.fill(child: mapBuilder(context, childLocation, fences)),

          // Floating top layer: child selector + geofence zone pills.
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 52),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSelector)
                      _ChildSelector(
                        options: childOptions,
                        selectedId: selectedChildId,
                        onSelect: onSelectChild,
                      ),
                    if (fences.isNotEmpty)
                      _ZonePills(fences: fences, childLocation: childLocation),
                  ],
                ),
              ),
            ),
          ),

          // Floating bottom layer: polished status card.
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: MinimalTrackingStatusBar(
              freshness: status.freshness,
              headline: l.trackingHeadline(status, childName, now),
              zoneLabel: status.currentZone == null ? null : l.t('tr_inside_zone', {'zone': status.currentZone}),
              distanceLabel: status.distanceFromHomeM == null ? null : l.distanceFromHome(status.distanceFromHomeM!),
              freshnessLabel: l.freshnessLabel(status.freshness),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom location status panel: a highly polished floating card whose
/// micro-copy is designed to reduce parental panic. "Delayed" reads as a warm
/// amber badge, never an aggressive red alarm.
///
/// Deliverable component for the map interface (Tab 3).
class MinimalTrackingStatusBar extends StatelessWidget {
  final Freshness freshness;
  final String headline;
  final String? zoneLabel;
  final String? distanceLabel;
  final String freshnessLabel;

  const MinimalTrackingStatusBar({
    super.key,
    required this.freshness,
    required this.headline,
    required this.freshnessLabel,
    this.zoneLabel,
    this.distanceLabel,
  });

  // Warm, low-anxiety palette: live = calm green, recent = calm blue, delayed =
  // soft amber (never red). Matches the spec's "reduce panic" intent.
  Color get _accent => switch (freshness) {
        Freshness.live => Palette.good,
        Freshness.recent => Palette.blue,
        Freshness.stale => Palette.amber,
      };

  IconData get _icon => switch (freshness) {
        Freshness.live => Icons.gps_fixed_rounded,
        Freshness.recent => Icons.near_me_rounded,
        Freshness.stale => Icons.access_time_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Palette.bgElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Palette.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 10), spreadRadius: -6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Freshness badge — colored, soft-tinted, with an icon + label.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_icon, size: 14, color: _accent),
                  const SizedBox(width: 6),
                  Text(freshnessLabel,
                      style: TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
              const Spacer(),
              if (distanceLabel != null)
                Text(distanceLabel!, style: const TextStyle(color: Palette.textDim, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(headline,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.25)),
          ),
          if (zoneLabel != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.place_rounded, size: 16, color: _accent),
              const SizedBox(width: 5),
              Text(zoneLabel!, style: const TextStyle(color: Palette.textDim, fontSize: 13.5)),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Geofence zone pills that float over the map. A green dot appears next to a
/// zone the child is currently detected inside.
class _ZonePills extends StatelessWidget {
  final List<Geofence> fences;
  final Coordinates? childLocation;
  const _ZonePills({required this.fences, required this.childLocation});

  bool _isInside(Geofence f) =>
      childLocation != null && checkGeofenceBoundary(childLocation!, f).inside;

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('home') || n.contains('дом') || n.contains('үй')) return Icons.home_rounded;
    if (n.contains('school') || n.contains('школ') || n.contains('мектеп')) return Icons.school_rounded;
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        children: [
          for (final f in fences)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ZonePill(name: f.name, icon: _iconFor(f.name), active: _isInside(f)),
            ),
        ],
      ),
    );
  }
}

class _ZonePill extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool active;
  const _ZonePill({required this.name, required this.icon, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.bgElevated,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: active ? Palette.good.withValues(alpha: 0.5) : Palette.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4), spreadRadius: -4),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: active ? Palette.good : Palette.textDim),
        const SizedBox(width: 7),
        Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: active ? Palette.text : Palette.textDim)),
        if (active) ...[
          const SizedBox(width: 7),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Palette.good, shape: BoxShape.circle)),
        ],
      ]),
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
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SelectorChip(
                label: o.name,
                selected: o.id == selectedId,
                onTap: () => onSelect?.call(o.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectorChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? Palette.roseViolet : null,
            color: selected ? null : Palette.bgElevated,
            borderRadius: BorderRadius.circular(30),
            border: selected ? null : Border.all(color: Palette.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4), spreadRadius: -4),
            ],
          ),
          child: Text(label,
              style: TextStyle(
                color: selected ? Colors.white : Palette.textDim,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              )),
        ),
      ),
    );
  }
}

class _FloatingTitle extends StatelessWidget {
  final String text;
  const _FloatingTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Palette.bgElevated,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4), spreadRadius: -4),
        ],
      ),
      child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.text)),
    );
  }
}

class _FloatingIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _FloatingIconButton({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Palette.bgElevated,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4), spreadRadius: -4),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Palette.text),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

class _FloatingActionChip extends StatelessWidget {
  final IconData icon;
  final void Function(String) onSelected;
  final List<PopupMenuEntry<String>> items;
  const _FloatingActionChip({required this.icon, required this.onSelected, required this.items});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Palette.bgElevated,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4), spreadRadius: -4),
        ],
      ),
      child: PopupMenuButton<String>(
        icon: Icon(icon, color: Palette.text),
        color: Palette.surfaceHi,
        onSelected: onSelected,
        itemBuilder: (_) => items,
      ),
    );
  }
}
