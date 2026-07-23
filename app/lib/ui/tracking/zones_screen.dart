/// Safe-zones management for a child — list, add, edit, and delete geofence
/// zones (name + radius + location). Reads/writes through the AppController's
/// upsertGeofence / removeGeofence. Reachable from the map's "+" menu.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/geofence.dart';
import '../../core/uuid.dart';
import '../../domain/geofence_alerts.dart' show visitsToZone;
import '../../data/device_location.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';
import '../widgets/permission_primer.dart';
import 'map_zone_picker.dart';

/// Google Maps needs a real key to render; the map picker is only offered when
/// the app is built with --dart-define=MAPS_ENABLED=true.
const bool _mapsEnabled = bool.fromEnvironment('MAPS_ENABLED', defaultValue: false);

class ZonesScreen extends StatelessWidget {
  final AppController controller;
  final String childId;
  const ZonesScreen({super.key, required this.controller, required this.childId});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('zones_title', {'name': _childName()}))),
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final child = _child();
            final zones = child?.geofences ?? const <Geofence>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (zones.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    child: Text(l.t('zones_empty'),
                        textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                  )
                else
                  for (final z in zones) ...[
                    _ZoneCard(
                      zone: z,
                      visits: visitsToZone(controller.alerts, child?.name ?? '', z.name),
                      onEdit: () => _openSheet(context, existing: z),
                      onDelete: () => _confirmDelete(context, z),
                    ),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openSheet(context),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: Text(l.t('zone_add')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: BorderSide(color: Palette.violet.withValues(alpha: 0.5)),
                    foregroundColor: Palette.violet,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  dynamic _child() {
    for (final c in controller.children) {
      if (c.id == childId) return c;
    }
    return null;
  }

  String _childName() => _child()?.name ?? '';

  Coordinates _defaultCenter() {
    final zones = _child()?.geofences ?? const <Geofence>[];
    for (final z in zones) {
      if (z.center != null) return z.center!;
    }
    return const Coordinates(43.238949, 76.889709); // Almaty fallback
  }

  Future<void> _confirmDelete(BuildContext context, Geofence z) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('confirm_remove_zone_title'),
      message: l.t('confirm_remove_zone_body', {'name': z.name}),
      confirmLabel: l.t('act_remove'),
    );
    if (ok) controller.removeGeofence(childId, z.id);
  }

  void _openSheet(BuildContext context, {Geofence? existing}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ZoneSheet(
          existing: existing,
          defaultCenter: _defaultCenter(),
          onSave: (fence) => controller.upsertGeofence(childId, fence),
        ),
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  final Geofence zone;
  final int visits; // recorded entries into this zone
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ZoneCard({required this.zone, required this.visits, required this.onEdit, required this.onDelete});

  IconData get _icon {
    final n = zone.name.toLowerCase();
    if (n.contains('home') || n.contains('дом') || n.contains('үй')) return Icons.home_rounded;
    if (n.contains('school') || n.contains('школ') || n.contains('мектеп')) return Icons.school_rounded;
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return GlassCard(
      onTap: onEdit,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Palette.violet.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(_icon, color: Palette.violet, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(zone.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  zone.shape == GeofenceShape.circle && zone.radiusM != null
                      ? '${l.t('zone_radius')} · ${l.t('zone_meters', {'m': zone.radiusM!.round()})}'
                      : l.t('zone_location_set'),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (visits > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: Palette.good.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.login_rounded, size: 12, color: Palette.good),
                const SizedBox(width: 4),
                Text(l.t('zone_visits', {'n': visits}),
                    style: const TextStyle(color: Palette.good, fontWeight: FontWeight.w700, fontSize: 11.5)),
              ]),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Palette.textDim),
            tooltip: l.t('act_remove'),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _ZoneSheet extends StatefulWidget {
  final Geofence? existing;
  final Coordinates defaultCenter;
  final void Function(Geofence) onSave;
  const _ZoneSheet({required this.existing, required this.defaultCenter, required this.onSave});

  @override
  State<_ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<_ZoneSheet> {
  late final TextEditingController _nameCtl;
  late double _radius;
  late Coordinates _center;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.existing?.name ?? '');
    _radius = widget.existing?.radiusM ?? 100;
    _center = widget.existing?.center ?? widget.defaultCenter;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<ZonePick>(MaterialPageRoute(
      builder: (_) => MapZonePickerScreen(initialCenter: _center, initialRadius: _radius),
    ));
    if (picked != null && mounted) {
      setState(() {
        _center = picked.center;
        _radius = picked.radius;
      });
    }
  }

  /// Move the zone centre to where the phone is.
  ///
  /// This used to fail in complete silence: a denied permission or a failed fix
  /// simply stopped the spinner, leaving the default centre in place. She would
  /// reasonably read that as success and save a zone around somewhere she has
  /// never been — and then get "left home" alerts about the wrong place, which
  /// is worse than having no zone at all.
  Future<void> _useCurrentLocation() async {
    // Explain WHY before the OS prompt, but only when it will actually appear
    // (permission not yet decided). If she declines the rationale, respect it
    // and don't fire the one-shot system dialog.
    if (await locationPermissionUndecided()) {
      if (!mounted) return;
      final proceed = await showPermissionPrimer(context, PermissionKind.location);
      if (!proceed) return;
    }
    setState(() => _locating = true);
    final result = await currentCoordinates();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (result.ok) _center = result.coords!;
    });
    if (!result.ok) {
      final l = L10nScope.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.t(result.messageKey!)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Palette.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(gradient: Palette.violetPink, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.place, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text(l.t(widget.existing == null ? 'zone_add' : 'zone_edit'),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 18),
          // Quick-fill name chips
          Wrap(spacing: 8, children: [
            for (final name in [l.t('onb_home_label'), l.t('onb_school_label'), l.t('zone_type_other')])
              ActionChip(
                label: Text(name),
                onPressed: () => setState(() => _nameCtl.text = name == l.t('zone_type_other') ? '' : name),
                backgroundColor: Palette.glass,
                side: const BorderSide(color: Palette.border),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.t('zone_name_hint')),
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 6),
          if (_mapsEnabled) ...[
            FilledButton.tonalIcon(
              onPressed: _pickOnMap,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(l.t('zone_pick_on_map')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: Palette.violet.withValues(alpha: 0.12),
                foregroundColor: Palette.violet,
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _locating ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 18),
            label: Text(l.t('zone_use_location')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Palette.border),
              foregroundColor: Palette.text,
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: Palette.border),
                  foregroundColor: Palette.textDim,
                ),
                child: Text(l.t('act_cancel')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  final name = _nameCtl.text.trim();
                  if (name.isEmpty) return;
                  final id = widget.existing?.id ?? uuidV4();
                  widget.onSave(Geofence.circle(id, name, _center, _radius));
                  Navigator.pop(context);
                },
                child: Text(l.t('act_save')),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
