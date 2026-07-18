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
import '../../domain/battery.dart';
import '../../domain/child_tracker_state.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
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
  final VoidCallback? onManageZones;
  final VoidCallback? onOpenAlerts;
  final int alertCount;
  final int? childAgeMonths; // for age-appropriate safety tips (null if no DOB)
  final int? batteryPct; // tracker battery %, null if unknown
  final List<BatteryReading> batteryHistory; // recent readings, oldest-first
  final DateTime? zoneEnteredAt; // when the child entered their current zone
  final VoidCallback? onCheckIn; // manual "arrived / all good" event
  final VoidCallback? onSos; // manual emergency signal (confirmed first)

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
    this.onManageZones,
    this.onOpenAlerts,
    this.alertCount = 0,
    this.childAgeMonths,
    this.batteryPct,
    this.batteryHistory = const [],
    this.zoneEnteredAt,
    this.onCheckIn,
    this.onSos,
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
          if (onOpenAlerts != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FloatingIconButton(
                icon: Icons.notifications_none_rounded,
                tooltip: l.t('alerts_title'),
                badgeCount: alertCount,
                onTap: onOpenAlerts!,
              ),
            ),
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
          if (onAddChild != null || onAddDevice != null || onManageZones != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FloatingActionChip(
                icon: Icons.add,
                tooltip: l.t('act_add'),
                onSelected: (v) {
                  if (v == 'child') onAddChild?.call();
                  if (v == 'device') onAddDevice?.call();
                  if (v == 'zones') onManageZones?.call();
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
                  if (onManageZones != null)
                    PopupMenuItem(value: 'zones', child: Row(children: [
                      const Icon(Icons.add_location_alt_outlined, size: 18, color: Palette.textDim),
                      const SizedBox(width: 10), Text(l.t('tr_manage_zones')),
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

          // Floating bottom layer: check-in / SOS actions + polished status card.
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onCheckIn != null || onSos != null) ...[
                  _ChildActionRow(
                    onCheckIn: onCheckIn,
                    onSos: onSos == null ? null : () => _confirmSos(context, l),
                  ),
                  const SizedBox(height: 10),
                ],
                MinimalTrackingStatusBar(
                  freshness: status.freshness,
                  headline: l.trackingHeadline(status, childName, now),
                  zoneLabel: status.currentZone == null ? null : l.t('tr_inside_zone', {'zone': status.currentZone}),
                  distanceLabel: status.distanceFromHomeM == null ? null : l.distanceFromHome(status.distanceFromHomeM!),
                  freshnessLabel: l.freshnessLabel(status.freshness),
                  batteryPct: batteryPct,
                  batteryHistory: batteryHistory,
                  now: now,
                  zoneEnteredAt: zoneEnteredAt,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSos(BuildContext context, L10n l) async {
    final ok = await confirmDestructive(
      context,
      title: l.t('sos_confirm_title'),
      message: l.t('sos_confirm_body'),
      confirmLabel: l.t('sos_confirm_send'),
    );
    if (!ok || !context.mounted) return;
    onSos?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('sos_sent')), behavior: SnackBarBehavior.floating, backgroundColor: Palette.danger),
    );
  }
}

/// The check-in + SOS action row that floats above the status card. Check-in is a
/// calm one-tap "all good"; SOS is a prominent danger button (confirmed first).
class _ChildActionRow extends StatelessWidget {
  final VoidCallback? onCheckIn;
  final VoidCallback? onSos;
  const _ChildActionRow({this.onCheckIn, this.onSos});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Row(
      children: [
        if (onCheckIn != null)
          Expanded(
            child: _ActionButton(
              icon: Icons.how_to_reg_rounded,
              label: l.t('child_checkin'),
              foreground: Palette.blue,
              filled: false,
              onTap: () {
                onCheckIn!();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.t('child_checkin_done')), behavior: SnackBarBehavior.floating),
                );
              },
            ),
          ),
        if (onCheckIn != null && onSos != null) const SizedBox(width: 10),
        if (onSos != null)
          Expanded(
            child: _ActionButton(
              icon: Icons.sos_rounded,
              label: l.t('child_sos'),
              foreground: Colors.white,
              filled: true,
              onTap: onSos!,
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.foreground, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? Palette.danger : Palette.bgElevated,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: filled ? null : Border.all(color: Palette.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4), spreadRadius: -4),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
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
  final int? batteryPct;
  final List<BatteryReading> batteryHistory;
  final DateTime? now;
  final DateTime? zoneEnteredAt; // when the child entered the current zone

  const MinimalTrackingStatusBar({
    super.key,
    required this.freshness,
    required this.headline,
    required this.freshnessLabel,
    this.zoneLabel,
    this.distanceLabel,
    this.batteryPct,
    this.batteryHistory = const [],
    this.now,
    this.zoneEnteredAt,
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
              if (batteryPct != null) ...[
                const SizedBox(width: 8),
                _BatteryChip(pct: batteryPct!, history: batteryHistory, now: now ?? DateTime.now()),
              ],
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
              Expanded(child: Text(zoneLabel!, style: const TextStyle(color: Palette.textDim, fontSize: 13.5))),
              if (_dwellLabel(context) != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: _accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule_rounded, size: 12, color: _accent),
                    const SizedBox(width: 4),
                    Text(_dwellLabel(context)!, style: TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
              ],
            ]),
          ],
        ],
      ),
    );
  }

  /// "for 2h 10m" — how long the child has been in the current zone, from the
  /// entry time. Null when unknown or not currently in a zone.
  String? _dwellLabel(BuildContext context) {
    if (zoneLabel == null || zoneEnteredAt == null || now == null) return null;
    final d = now!.difference(zoneEnteredAt!);
    if (d.isNegative) return null;
    return L10nScope.of(context).t('tr_in_zone_for', {'dur': _shortDuration(d)});
  }

  String _shortDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

/// Tracker battery chip: an icon + "%", coloured by level (critical red, low
/// amber, otherwise a calm neutral). Sits next to the freshness badge.
class _BatteryChip extends StatelessWidget {
  final int pct;
  final List<BatteryReading> history;
  final DateTime now;
  const _BatteryChip({required this.pct, this.history = const [], required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final level = batteryLevel(pct);
    final (color, icon) = switch (level) {
      BatteryLevel.critical => (Palette.danger, Icons.battery_alert_rounded),
      BatteryLevel.low => (Palette.amber, Icons.battery_2_bar_rounded),
      BatteryLevel.ok => (Palette.textDim, Icons.battery_5_bar_rounded),
      BatteryLevel.full => (Palette.good, Icons.battery_full_rounded),
    };
    final tappable = history.length >= 2;
    final chip = Semantics(
      label: l.t('tr_battery', {'pct': pct}),
      button: tappable,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text('$pct%', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          if (tappable) ...[
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded, size: 14, color: color),
          ],
        ]),
      ),
    );
    if (!tappable) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () => _showHistory(context, l),
      child: chip,
    );
  }

  void _showHistory(BuildContext context, L10n l) {
    final change = batteryChange(history);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) {
        final recent = history.reversed.toList(); // newest-first for display
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(l.t('bat_history_title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                change == 0
                    ? l.t('bat_change_flat')
                    : l.t(change < 0 ? 'bat_change_down' : 'bat_change_up', {'n': change.abs()}),
                style: const TextStyle(color: Palette.textDim, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const Divider(height: 14, color: Palette.border),
                  itemBuilder: (_, i) {
                    final r = recent[i];
                    final level = batteryLevel(r.pct);
                    final color = switch (level) {
                      BatteryLevel.critical => Palette.danger,
                      BatteryLevel.low => Palette.amber,
                      BatteryLevel.ok => Palette.textDim,
                      BatteryLevel.full => Palette.good,
                    };
                    final age = now.difference(r.at);
                    return Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: color),
                        const SizedBox(width: 12),
                        Text('${r.pct}%', style: TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: color, fontSize: 15)),
                        const Spacer(),
                        Text(l.ago(age.isNegative ? Duration.zero : age), style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
  final int badgeCount;
  const _FloatingIconButton({required this.icon, required this.tooltip, required this.onTap, this.badgeCount = 0});
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
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
        ),
        if (badgeCount > 0)
          Positioned(
            right: 2, top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: Palette.danger,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Palette.bg, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(badgeCount > 9 ? '9+' : '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }
}

class _FloatingActionChip extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final void Function(String) onSelected;
  final List<PopupMenuEntry<String>> items;
  const _FloatingActionChip({required this.icon, required this.tooltip, required this.onSelected, required this.items});
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
        tooltip: tooltip,
        color: Palette.surfaceHi,
        onSelected: onSelected,
        itemBuilder: (_) => items,
      ),
    );
  }
}
