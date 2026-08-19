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
import '../../domain/offline.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';
import '../widgets/battery_colors.dart';
import '../widgets/confirm.dart';
import 'child_safety_screen.dart';

typedef MapBuilder = Widget Function(
    BuildContext context, Coordinates? child, List<Geofence> fences);

typedef ChildOption = ({String id, String name});

class ChildMapScreen extends StatelessWidget {
  final String childName;

  /// False when no child has been added yet, which is the ordinary state for a
  /// first-time expectant mother. The title and the waiting line then use
  /// wording that needs no name, because no generic noun declines correctly in
  /// both Russian sentences.
  final bool hasNamedChild;
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
  final DateTime? lastCheckInAt; // when the child last checked in
  /// Manual "arrived / all good" event. Returns whether the SERVER took it —
  /// same reason as [onSos], one notch down in stakes: the feed row now marks
  /// an undelivered check-in «не отправлено», so a snackbar that says
  /// «Отметка отправлена» regardless would contradict the row it just wrote.
  final Future<bool> Function()? onCheckIn;

  /// Manual emergency signal (confirmed first).
  ///
  /// **Returns whether the SERVER took it.** It was a `VoidCallback?`, and that
  /// type is the defect: it structurally cannot report a failure, so this
  /// screen printed «Сигнал SOS отправлен» after calling it and had nothing to
  /// check. Underneath, `pushed()` stays silent for anything that is not a 4xx
  /// — offline, 5xx, timeout, expired session — and there is deliberately no
  /// replay, so nothing retried and nothing ever told her. She reads that her
  /// SOS was sent while no relative is pushed and the back-office safety feed
  /// has no row.
  final Future<bool> Function()? onSos;
  /// Opens screen 47, «История дня». Null where nothing can load a trail —
  /// the row then shows two buttons rather than a dead third.
  final VoidCallback? onDayHistory;

  /// Opens the child's card — the whole child-care hub: медкарта, прививки,
  /// рост и вес, развитие, дневник новорождённого, детектор плача, прикорм,
  /// безопасность дома, болезни.
  ///
  /// That hub had exactly one entry point in the entire app, three taps down
  /// Настройки, and the «Бала» tab it belongs to had no route to it at all —
  /// so everything under it was effectively unshipped. Null when no child is
  /// selected: the card needs one, and an icon that opens nothing is worse
  /// than an absent icon.
  final VoidCallback? onOpenChildCard;

  /// Screen 15a — the tools list: Медкарта, Прививки, Рост и вес, Развитие,
  /// Дневник малыша, Детектор плача, Прикорм, Безопасность дома, Болезни.
  ///
  /// A LABELLED control, unlike the four glyphs in the app bar. Those nine
  /// screens were three taps down an unlabelled folder icon on a full-bleed
  /// map, which is the same as not shipping them: nothing on this tab said
  /// they existed. Null when no child is selected — there is nothing to open
  /// them about.
  final VoidCallback? onOpenTools;

  /// Screen 20. No connection, from the connectivity service.
  final bool isOffline;

  /// Try again. Returns false when it still could not reach the server, so the
  /// button can say so instead of pretending it refreshed.
  final Future<bool> Function()? onRefresh;

  /// Whether a tracker is linked to this child. When false and there is no
  /// location, the status bar guides her to pair one instead of implying a
  /// fix is on its way. Defaults true so existing callers/tests are unchanged.
  final bool hasPairedTracker;

  const ChildMapScreen({
    super.key,
    required this.childName,
    this.hasNamedChild = true,
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
    this.lastCheckInAt,
    this.onCheckIn,
    this.onSos,
    this.onDayHistory,
    this.onOpenChildCard,
    this.onOpenTools,
    this.isOffline = false,
    this.onRefresh,
    this.hasPairedTracker = true,
  });

  /// Screen 20's condition: the map must stop looking live.
  ///
  /// Two separate causes, one consequence — no connection, or a fix too old to
  /// call current. Treating only the first would leave a phone with four bars
  /// and a tracker that stopped reporting an hour ago drawing a confident pin.
  bool get _staleMap => mapShouldLookStale(
        offline: isOffline,
        sinceLastFix: updatedAt == null ? null : now.difference(updatedAt!),
      );

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
    final showSelector = childOptions.length > 1 ||
        (childOptions.isNotEmpty && onAddChild != null);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _FloatingTitle(hasNamedChild
            ? l.t('tr_title', {'name': childName})
            : l.t('tr_title_nochild')),
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
          // «Карточка ребёнка» — the child-care hub. First of the three, because
          // it is the only one of them that is a whole section of the app
          // rather than a single screen, and it had no route from this tab at
          // all: медкарта, прививки, рост, развитие, дневник, плач, прикорм,
          // безопасность дома and болезни all hung off Настройки and nothing
          // else.
          if (onOpenChildCard != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FloatingIconButton(
                icon: Icons.folder_shared_outlined,
                tooltip: l.t('tr_child_card'),
                onTap: onOpenChildCard!,
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
          if (onAddChild != null ||
              onAddDevice != null ||
              onManageZones != null)
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
                    PopupMenuItem(
                        value: 'child',
                        child: Row(children: [
                          const Icon(Icons.child_care,
                              size: 18, color: Palette.textDim),
                          const SizedBox(width: 10),
                          Text(l.t('tr_add_child')),
                        ])),
                  if (onAddDevice != null)
                    PopupMenuItem(
                        value: 'device',
                        child: Row(children: [
                          const Icon(Icons.watch,
                              size: 18, color: Palette.textDim),
                          const SizedBox(width: 10),
                          Text(l.t('tr_add_device')),
                        ])),
                  if (onManageZones != null)
                    PopupMenuItem(
                        value: 'zones',
                        child: Row(children: [
                          const Icon(Icons.add_location_alt_outlined,
                              size: 18, color: Palette.textDim),
                          const SizedBox(width: 10),
                          Text(l.t('tr_manage_zones')),
                        ])),
                ],
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Full-bleed map surface.
          //
          // Screen 20: when there is no connection, or the last fix is too old
          // to call current, the colour comes out of it. A map that looks
          // exactly the same at one minute and at forty is how «она дома» gets
          // said about a position from half an hour ago.
          Positioned.fill(
            child: _staleMap
                ? ColorFiltered(
                    // Fully desaturated, not merely dimmed: a dimmed map still
                    // reads as a map at night, and this has to be unmistakable
                    // in daylight on a phone held at arm's length.
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0, 0, 0, 1, 0,
                    ]),
                    child: mapBuilder(context, childLocation, fences),
                  )
                : mapBuilder(context, childLocation, fences),
          ),

          // Floating top layer: child selector + geofence zone pills.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
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
                    // Screen 20's two amber plates. The first says why, the
                    // second says how old what is on screen actually is —
                    // stated in words, because a timestamp on its own gets
                    // read as "recent" by anyone not doing arithmetic.
                    if (_staleMap) ...[
                      const SizedBox(height: 10),
                      _OfflinePlate(
                        offline: isOffline,
                        age: dataAge(updatedAt, now),
                        onRefresh: onRefresh,
                        onWhatNow: () => _showOfflineHelp(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Floating bottom layer: check-in / SOS actions + polished status card.
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Screen 15a's list of tools, named on the tab it belongs to.
                // Above the safety actions, because it is a destination rather
                // than an action — and below nothing, because the map is what
                // this tab opens on.
                if (onOpenTools != null) ...[
                  _ChildToolsButton(onTap: onOpenTools!),
                  const SizedBox(height: 10),
                ],
                if (onCheckIn != null || onSos != null || onDayHistory != null) ...[
                  _ChildActionRow(
                    onCheckIn: onCheckIn,
                    onSos: onSos == null ? null : () => _confirmSos(context, l),
                    onDayHistory: onDayHistory,
                  ),
                  const SizedBox(height: 10),
                ],
                MinimalTrackingStatusBar(
                  // Offline forces stale. Without it the card said «В сети ·
                  // обновлено только что» directly beneath an amber «Нет
                  // интернета» — two of the app's own elements contradicting
                  // each other about the one fact the screen exists to state.
                  freshness: _staleMap ? Freshness.stale : status.freshness,
                  headline: l.trackingHeadline(status, childName, now, named: hasNamedChild),
                  zoneLabel: status.currentZone == null
                      ? null
                      : l.t('tr_inside_zone', {'zone': status.currentZone}),
                  distanceLabel: status.distanceFromHomeM == null
                      ? null
                      : l.distanceFromHome(status.distanceFromHomeM!),
                  // Same override as the dot above it: the label is passed
                  // separately, so fixing only one left «В сети» beside a grey
                  // map and an amber «Нет интернета».
                  freshnessLabel:
                      l.freshnessLabel(_staleMap ? Freshness.stale : status.freshness),
                  // A battery belongs to a DEVICE. With no tracker linked,
                  // the last stored reading is about a tracker that is not on
                  // this child — and the card showed «8 %» directly above
                  // «Трекер ещё не привязан», which reads as a contradiction
                  // and quietly invites her to trust a number about nothing.
                  batteryPct: hasPairedTracker ? batteryPct : null,
                  batteryHistory: hasPairedTracker ? batteryHistory : const [],
                  now: now,
                  zoneEnteredAt: zoneEnteredAt,
                  lastCheckInAt: lastCheckInAt,
                  // No location AND no tracker linked → guide her to pair one,
                  // rather than "Waiting…" that would never resolve on its own.
                  hint: (childLocation == null && !hasPairedTracker)
                      ? l.t('tr_no_tracker_hint')
                      : null,
                  trackerLinked: hasPairedTracker,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Confirm, send, and say WHICH of the two things happened.
  ///
  /// Modelled on the account-erase path in `settings_screen.dart`, which
  /// already distinguishes «Все данные удалены» from «Данные удалены с
  /// телефона. Копию на сервере удалить не удалось». Same shape, higher
  /// stakes: «отправлен» is a claim about the family being notified, and if the
  /// request did not land, repeating it is the false promise this whole change
  /// exists to remove. An SOS that did not reach the server must never render
  /// as one that did.
  Future<void> _confirmSos(BuildContext context, L10n l) async {
    final send = onSos;
    if (send == null) return;
    final ok = await confirmDestructive(
      context,
      title: l.t('sos_confirm_title'),
      message: l.t('sos_confirm_body'),
      confirmLabel: l.t('sos_confirm_send'),
    );
    if (!ok || !context.mounted) return;

    // The messenger is captured before the await: the send is a network round
    // trip and this screen may well be gone by the time it answers.
    final messenger = ScaffoldMessenger.of(context);
    // «Отправляем…» — not a claim, a state. Without it the phone looks like it
    // did nothing at all for however long the request takes, which on a bad
    // connection is the whole timeout.
    messenger.showSnackBar(SnackBar(
      content: Text(l.t('sos_sending')),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.danger,
      duration: const Duration(minutes: 1),
    ));

    final sent = await send();

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(l.t(sent ? 'sos_sent' : 'sos_not_sent')),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.danger,
      // Longer when it failed: it names what she should do instead, and it is
      // the one message on this screen she must not miss.
      duration: Duration(seconds: sent ? 4 : 10),
    ));
  }
}

/// Screen 20 — «Что можно сделать».
///
/// Opened from the amber plate. Four lines, and the first one is the one that
/// matters: the tracker's SOS button does not go through this phone. A parent
/// who has just found out she has no connection is working out whether her
/// child is protected, and that is the answer.
void _showOfflineHelp(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      final l = L10nScope.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('off_what_now'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              for (final a in offlineActions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        a == OfflineAction.childSosStillWorks
                            ? Icons.shield_rounded
                            : Icons.check_rounded,
                        size: 18,
                        color: a == OfflineAction.childSosStillWorks
                            ? Ds.mintText
                            : Palette.textDim,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(l.t(a.l10nKey),
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: a == OfflineAction.childSosStillWorks
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            )),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The amber plate: why the map is grey, how old what is on it is, and the two
/// things to do about it.
class _OfflinePlate extends StatefulWidget {
  final bool offline;
  final DataAge? age;
  final Future<bool> Function()? onRefresh;
  final VoidCallback onWhatNow;

  const _OfflinePlate({
    required this.offline,
    required this.age,
    required this.onRefresh,
    required this.onWhatNow,
  });

  @override
  State<_OfflinePlate> createState() => _OfflinePlateState();
}

class _OfflinePlateState extends State<_OfflinePlate> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy || widget.onRefresh == null) return;
    setState(() => _busy = true);
    final ok = await widget.onRefresh!();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      // Said out loud. A refresh button that quietly does nothing teaches her
      // the app is broken rather than that the connection is.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10nScope.of(context).t('off_refresh_failed')),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  String _ageLine(L10n l) {
    final a = widget.age;
    if (a == null) return l.t('off_no_data');
    final time = '${a.at.hour.toString().padLeft(2, '0')}:'
        '${a.at.minute.toString().padLeft(2, '0')}';
    // Past an hour, minutes stop being the useful unit — «Данные от 14:32 ·
    // 190 минут назад» is arithmetic homework.
    return a.overAnHour
        ? l.t('off_data_from_h', {'time': time, 'n': a.hoursAgo})
        : l.t('off_data_from', {'time': time, 'n': a.minutesAgo});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Ds.pastelButter,
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.offline)
            Row(
              children: [
                const Icon(Icons.wifi_off_rounded, size: 17, color: Ds.amberText),
                const SizedBox(width: 8),
                Text(l.t('off_no_internet'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Ds.amberText)),
              ],
            ),
          if (widget.offline) const SizedBox(height: 6),
          Text(_ageLine(l),
              style: const TextStyle(fontSize: 13, color: Ds.text)),
          const SizedBox(height: 10),
          // Stacked, not side by side. «Что можно сделать» and «Обновить»
          // together overflowed a 390 dp phone by 115 px in Russian, which put
          // the refresh button off the right edge where nothing could reach
          // it — on the screen a parent opens when she cannot find her child.
          if (widget.onRefresh != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _refresh,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, DsShape.minTapTarget),
                ),
                child: Text(l.t('off_refresh')),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: widget.onWhatNow,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, DsShape.minTapTarget),
                foregroundColor: Ds.text,
              ),
              child: Text(l.t('off_what_now')),
            ),
          ),
        ],
      ),
    );
  }
}

/// The labelled way into screen 15a's tools, floating over the map.
///
/// Labelled on purpose. This tab already carries four unlabelled glyphs, and
/// the one of them that hid nine care screens was a folder — a caption is the
/// whole difference between a control somebody finds and one somebody does not.
class _ChildToolsButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ChildToolsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: DsShape.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Palette.bgElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            boxShadow: DsShape.hardShadow,
          ),
          child: Row(
            children: [
              const Icon(Icons.grid_view_rounded,
                  size: 20, color: Palette.violet),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.t('tr_tools'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Palette.text)),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Palette.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// The check-in + SOS action row that floats above the status card. Check-in is a
/// calm one-tap "all good"; SOS is a prominent danger button (confirmed first).
class _ChildActionRow extends StatelessWidget {
  final Future<bool> Function()? onCheckIn;
  final VoidCallback? onSos;
  final VoidCallback? onDayHistory;
  const _ChildActionRow({this.onCheckIn, this.onSos, this.onDayHistory});

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
              onTap: () async {
                // Captured before the await — the row can be gone by the time
                // the request answers.
                final messenger = ScaffoldMessenger.of(context);
                final sent = await onCheckIn!();
                messenger.showSnackBar(
                  SnackBar(
                      content: Text(
                          l.t(sent ? 'child_checkin_done' : 'child_checkin_local')),
                      behavior: SnackBarBehavior.floating),
                );
              },
            ),
          ),
        // «История дня» — the spec's second button on this row. The trail has
        // been recorded and pruned all along with no way in; this is it.
        if (onDayHistory != null) ...[
          if (onCheckIn != null) const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              icon: Icons.timeline_rounded,
              label: l.t('day_history'),
              foreground: Palette.blue,
              filled: false,
              onTap: onDayHistory!,
            ),
          ),
        ],
        if ((onCheckIn != null || onDayHistory != null) && onSos != null)
          const SizedBox(width: 10),
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
  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.foreground,
      required this.filled,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      // Transparent, with the fill moved onto the Container below. The colour
      // used to live here while the Container drew the hard shadow — and an
      // unblurred ink rectangle behind a Container that has no fill of its own
      // reads through the whole button, so both actions rendered solid ink.
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? Palette.danger : Palette.bgElevated,
            borderRadius: BorderRadius.circular(18),
            // Both variants carry the outline. The filled one skipped it, which
            // left the SOS button as the only control on the screen without an
            // edge — in this system that reads as unfinished, not as emphasis.
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            boxShadow: [
              ...DsShape.hardShadow,
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8),
                // The Russian labels are long enough that the pair overflowed
                // by a hair once each button gained its 2px outline.
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ],
            ),
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
  final DateTime? lastCheckInAt; // when the child last checked in

  /// A gentle guidance line under the headline — e.g. "pair a tracker" when
  /// there is no location because no device is linked, so "Waiting…" does not
  /// read as an arrival that is merely late. Null hides it.
  final String? hint;

  /// Whether a tracker is actually linked to this child.
  ///
  /// With none, "Задержка" is describing a device that does not exist — it
  /// says a report is late when nothing was ever going to report. The badge is
  /// hidden in that case; the hint under the headline is the honest answer.
  final bool trackerLinked;

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
    this.lastCheckInAt,
    this.hint,
    this.trackerLinked = true,
  });

  // Warm, low-anxiety palette: live = calm green, recent = calm blue, delayed =
  // soft amber (never red). Matches the spec's "reduce panic" intent.
  Color get _accent => switch (freshness) {
        Freshness.live => Palette.good,
        Freshness.recent => Palette.blue,
        Freshness.stale => Palette.amber,
      };

  /// The same status, at a contrast a person can actually read.
  ///
  /// `_accent` is a FILL. It was being used for the label as well, on a 14 %
  /// tint of itself, which measures:
  ///
  ///   live    #17A97A on its own tint — 2.62:1
  ///   delayed #E08A00 on its own tint — 2.38:1
  ///   recent  #1F5FBF on its own tint — 4.96:1  (the only one that passed)
  ///
  /// 13 px bold needs 4.5:1. So the one claim this screen exists to make — how
  /// current the position is — was rendered illegibly in exactly the two states
  /// that matter: «she is fine» and «this is late». The blue middle state
  /// passed, which is why it never looked obviously broken.
  ///
  /// The `*Text` tokens exist for precisely this pairing. The rule, stated once
  /// so it stops being rediscovered: **text on an accent tint is always the
  /// `*Text` token, never the fill token.**
  Color get _accentText => switch (freshness) {
        Freshness.live => Ds.mintText,
        Freshness.recent => Ds.blueText,
        Freshness.stale => Ds.amberText,
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
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        boxShadow: [
          ...DsShape.hardShadow,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Freshness badge — colored, soft-tinted, with an icon + label.
              // Flexible: the ink outline added 4px to every chip on this row,
              // and this one was already at the edge of the width — it
              // overflowed by 64px with a long Russian freshness label. The
              // badge now gives way before the row does.
              if (trackerLinked)
                Flexible(
                  child: Container(
                    key: const Key('freshness-badge'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: Ds.ink, width: DsShape.borderWidth),
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // The glyph keeps the fill colour: an icon is a shape, and
                      // WCAG's 4.5:1 is a rule about text. The label does not.
                      Icon(_icon, size: 14, color: _accentText),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(freshnessLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: _accentText,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                    ]),
                  ),
                ),
              if (batteryPct != null) ...[
                const SizedBox(width: 8),
                _BatteryChip(
                    pct: batteryPct!,
                    history: batteryHistory,
                    now: now ?? DateTime.now()),
              ],
              const Spacer(),
              // Also flexible: with a battery chip and a long freshness label
              // all three items no longer fit once each gained a 2px outline.
              if (distanceLabel != null)
                Flexible(
                  child: Text(distanceLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(headline,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700, height: 1.25)),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.info_outline_rounded,
                  size: 15, color: Palette.textDim),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(hint!,
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 13, height: 1.35))),
            ]),
          ],
          if (zoneLabel != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.place_rounded, size: 16, color: _accent),
              const SizedBox(width: 5),
              Expanded(
                  child: Text(zoneLabel!,
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 13.5))),
              if (_dwellLabel(context) != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      border:
                          Border.all(color: Ds.ink, width: DsShape.borderWidth),
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  // Same tint, same rule — and worse here, because 12 px bold
                  // has the same 4.5:1 floor as 13 px.
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule_rounded, size: 12, color: _accentText),
                    const SizedBox(width: 4),
                    Text(_dwellLabel(context)!,
                        style: TextStyle(
                            color: _accentText,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ]),
                ),
              ],
            ]),
          ],
          if (lastCheckInAt != null && now != null) ...[
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final l = L10nScope.of(context);
              final age = now!.difference(lastCheckInAt!);
              return Row(children: [
                const Icon(Icons.how_to_reg_rounded,
                    size: 16, color: Palette.blue),
                const SizedBox(width: 5),
                // Flexible, so the sentence wraps instead of running off the
                // side. At 360dp with the font-size slider at 130% this line
                // overran by 51px, and Flutter paints the striped overflow bar
                // over the content rather than clipping it — so the parent who
                // most needs larger text got the worst version of this screen.
                Flexible(
                  child: Text(
                      l.t('tr_last_checkin',
                          {'ago': l.ago(age.isNegative ? Duration.zero : age)}),
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 13)),
                ),
              ]);
            }),
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
    // Use the shared localized formatter. Hand-rolling it here printed English
    // units inside a Russian sentence — "уже 1m" instead of "уже 1 мин".
    final l = L10nScope.of(context);
    return l.t('tr_in_zone_for', {'dur': l.duration(d.inMinutes)});
  }
}

/// Tracker battery chip: an icon + "%", coloured by level (critical red, low
/// amber, otherwise a calm neutral). Sits next to the freshness badge.
class _BatteryChip extends StatelessWidget {
  final int pct;
  final List<BatteryReading> history;
  final DateTime now;
  const _BatteryChip(
      {required this.pct, this.history = const [], required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final level = batteryLevel(pct);
    // The colour comes from one place for every screen; the ICON is what
    // separates critical from low, because they share amber on purpose —
    // «Красный только SOS».
    final color = batteryColor(pct);
    final icon = switch (level) {
      BatteryLevel.critical => Icons.battery_alert_rounded,
      BatteryLevel.low => Icons.battery_2_bar_rounded,
      BatteryLevel.ok => Icons.battery_5_bar_rounded,
      BatteryLevel.full => Icons.battery_full_rounded,
    };
    final tappable = history.length >= 2;
    final chip = Semantics(
      label: l.t('tr_battery', {'pct': pct}),
      button: tappable,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text('$pct%',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
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
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Palette.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(l.t('bat_history_title'),
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                change == 0
                    ? l.t('bat_change_flat')
                    : l.t(change < 0 ? 'bat_change_down' : 'bat_change_up',
                        {'n': change.abs()}),
                style: const TextStyle(color: Palette.textDim, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: recent.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 14, color: Palette.border),
                  itemBuilder: (_, i) {
                    final r = recent[i];
                    // A third copy of the same table lived here — which is
                    // exactly how one of them stays red after the others are
                    // fixed.
                    final color = batteryColor(r.pct);
                    final age = now.difference(r.at);
                    return Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: color),
                        const SizedBox(width: 12),
                        Text('${r.pct}%',
                            style: TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontWeight: FontWeight.w700,
                                color: color,
                                fontSize: 15)),
                        const Spacer(),
                        Text(l.ago(age.isNegative ? Duration.zero : age),
                            style: const TextStyle(
                                color: Palette.textDim, fontSize: 12.5)),
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
    if (n.contains('home') || n.contains('дом') || n.contains('үй'))
      return Icons.home_rounded;
    if (n.contains('school') || n.contains('школ') || n.contains('мектеп'))
      return Icons.school_rounded;
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
              child: _ZonePill(
                  name: f.name, icon: _iconFor(f.name), active: _isInside(f)),
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
  const _ZonePill(
      {required this.name, required this.icon, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.bgElevated,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
            color:
                active ? Palette.good.withValues(alpha: 0.5) : Palette.border),
        boxShadow: [
          ...DsShape.hardShadow,
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: active ? Palette.good : Palette.textDim),
        const SizedBox(width: 7),
        Text(name,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: active ? Palette.text : Palette.textDim)),
        if (active) ...[
          const SizedBox(width: 7),
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Palette.good, shape: BoxShape.circle)),
        ],
      ]),
    );
  }
}

class _ChildSelector extends StatelessWidget {
  final List<ChildOption> options;
  final String? selectedId;
  final void Function(String id)? onSelect;
  const _ChildSelector(
      {required this.options, required this.selectedId, this.onSelect});

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
  const _SelectorChip(
      {required this.label, required this.selected, required this.onTap});

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
            color: selected ? Ds.coralCta : Palette.bgElevated,
            borderRadius: BorderRadius.circular(30),
            border: selected
                ? null
                : Border.all(color: Ds.ink, width: DsShape.borderWidth),
            boxShadow: [
              ...DsShape.hardShadow,
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
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        color: Palette.bgElevated,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          ...DsShape.hardShadow,
        ],
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: Palette.text)),
    );
  }
}

class _FloatingIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;
  const _FloatingIconButton(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.badgeCount = 0});
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
              ...DsShape.hardShadow,
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
            right: 2,
            top: 2,
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
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
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
  const _FloatingActionChip(
      {required this.icon,
      required this.tooltip,
      required this.onSelected,
      required this.items});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Palette.bgElevated,
        shape: BoxShape.circle,
        boxShadow: [
          ...DsShape.hardShadow,
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
