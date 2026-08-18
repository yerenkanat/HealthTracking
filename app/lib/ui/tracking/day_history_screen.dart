/// Screen 47 — «История дня».
///
/// «шапка + «Календарь» → карта маршрута с точками + плашка «3,2 км · 4 точки»
/// → таймлайн событий (вышла, пришла в школу, SOS, дома) → плашка «маршруты
/// хранятся 90 дней».»
///
/// The trail has been recorded on every fix since the first one and deleted at
/// ninety days, and until now there was nothing that could look at it. This is
/// the looking.
///
/// The design's closing plashka is the one thing here that is NOT built as
/// drawn. See [_RetentionNote]: «маршруты хранятся 90 дней» is a promise about
/// `location_history`, and the list it sits under is zone crossings and SOS,
/// which live in other tables that nothing sweeps.
///
/// Like [ChildMapScreen], the map itself is a platform view that cannot render
/// in a widget test, so it sits behind [routeMapBuilder] — the default builds
/// the real one, tests inject a stub, and everything floating above it is plain
/// widgets and IS tested.
library;

import 'package:flutter/material.dart';
import '../../domain/day_history.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import 'day_event_screen.dart';

typedef RouteMapBuilder = Widget Function(
    BuildContext context, List<RoutePoint> points, List<DayEvent> events);

/// Loads one day. Returns the parsed history, or throws — the screen shows a
/// failure differently from an empty day, and cannot tell them apart from null.
typedef DayLoader = Future<DayHistory> Function(String day);

class DayHistoryScreen extends StatefulWidget {
  final String childName;
  final DayLoader load;
  final RouteMapBuilder routeMapBuilder;

  /// Today, injected so the calendar's upper bound is testable.
  final DateTime now;

  /// Which day to open on. Defaults to [now].
  final DateTime? initialDay;

  /// Records the parent's verdict on an SOS. Passed straight through to the
  /// detail screen, which hides «Чем закончилось» entirely when it is null —
  /// so omitting it here removes the section rather than breaking it.
  final SosOutcomeSaver? onSaveOutcome;

  const DayHistoryScreen({
    super.key,
    required this.childName,
    required this.load,
    required this.routeMapBuilder,
    required this.now,
    this.initialDay,
    this.onSaveOutcome,
  });

  @override
  State<DayHistoryScreen> createState() => _DayHistoryScreenState();
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _DayHistoryScreenState extends State<DayHistoryScreen> {
  late DateTime _day = widget.initialDay ?? widget.now;
  DayHistory? _history;

  /// Three states, not two. An empty day and a failed load look identical if
  /// the screen only knows "have data / do not", and they call for opposite
  /// responses: one is "the tracker was off", the other is "try again".
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Record a saved verdict in the day already on screen.
  ///
  /// Local rather than a refetch: the server has confirmed the write, and
  /// reloading the whole day would scroll the list back to the top under a
  /// parent who has just tapped something near the bottom of it.
  void _applyOutcome(DayEvent event, SosOutcome outcome) {
    final h = _history;
    if (h == null || !mounted) return;
    setState(() {
      _history = DayHistory(
        day: h.day,
        points: h.points,
        distanceM: h.distanceM,
        rawCount: h.rawCount,
        events: [
          for (final e in h.events)
            e.at == event.at && e.kind == event.kind ? e.withOutcome(outcome) : e,
        ],
        retentionDays: h.retentionDays,
      );
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final h = await widget.load(_ymd(_day));
      if (!mounted) return;
      setState(() {
        _history = h;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        // The previous day's route is cleared rather than left on screen under
        // a failure banner: a map showing yesterday under today's date is
        // worse than a map showing nothing.
        _history = null;
      });
    }
  }

  Future<void> _pickDay() async {
    final l = L10nScope.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      // The retention window is the real lower bound — there is nothing to show
      // before it, and offering the date is offering an empty screen.
      firstDate: widget.now.subtract(
        Duration(days: _history?.retentionDays ?? 90),
      ),
      lastDate: widget.now,
      helpText: l.t('day_calendar'),
    );
    if (picked == null) return;
    setState(() => _day = picked);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final h = _history;

    return Scaffold(
      backgroundColor: Ds.cream,
      appBar: AppBar(
        title: Text(l.t('day_history')),
        actions: [
          TextButton.icon(
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(l.t('day_calendar')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(_ymd(_day), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ds.textSecondary)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            _FailureCard(onRetry: _reload)
          else if (h == null || h.isEmpty)
            const _EmptyDayCard()
          else ...[
            _RouteCard(
              history: h,
              builder: widget.routeMapBuilder,
            ),
            // Said out loud rather than left as a discrepancy between a badge
            // reading «4 точки» and a tracker that reports every half minute.
            if (h.wasSimplified) ...[
              const SizedBox(height: 8),
              Text(
                l.t('day_simplified', {'raw': h.rawCount, 'n': h.pointCount}),
                style: const TextStyle(
                    fontSize: 12, height: 1.35, color: Ds.textSecondary),
              ),
            ],
            const SizedBox(height: 18),
            Text(l.t('day_timeline'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
            const SizedBox(height: 10),
            _Timeline(
              history: h,
              childName: widget.childName,
              routeMapBuilder: widget.routeMapBuilder,
              onSaveOutcome: widget.onSaveOutcome,
              onSaved: _applyOutcome,
            ),
          ],
          const SizedBox(height: 20),
          // Printed on every state, including the empty one. It is a promise
          // about the data that is not there as much as about the data that is
          // — but only the events half of it is unconditional. The route half
          // needs a route: see [_RetentionNote].
          _RetentionNote(
            routeDays: h != null && h.points.isNotEmpty ? h.retentionDays : null,
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final DayHistory history;
  final RouteMapBuilder builder;
  const _RouteCard({required this.history, required this.builder});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          SizedBox(
            height: 260,
            width: double.infinity,
            child: builder(context, history.points, history.events),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                l.t('day_route_badge', {
                  'd': formatDistance(history.distanceM),
                  'n': history.pointCount,
                }),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Ds.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What actually happens to what is on this screen — which is two answers, so
/// two lines.
///
/// It used to be one: «Маршруты хранятся 90 дней, потом удаляются
/// автоматически», printed unconditionally with the number read from the
/// server. Every word of it is true about `location_history`, and none of it is
/// true about the list directly beneath it. Zone crossings (`geofence_events`)
/// and SOS rows (`safety_alerts`) are not routes; the sweep in
/// `packages/backend/src/privacy/retention.ts` does not touch them, and nothing
/// else does either — they live until the account is deleted. A mother reading
/// «хранится 90 дней» over her daughter's SOS was being told the opposite of
/// what happens to it.
///
/// So:
///
///  * [routeDays] is null unless the server actually returned a route, and the
///    period is printed only then. The 90-day rule is real, but no code path in
///    `app/lib` sends a location fix today — `enqueueLocation` in
///    `net/telemetry_batcher.dart` has no caller outside `tool/` — so on every
///    real day the store it governs is empty, and a retention promise over an
///    empty map is a claim about nothing. When somebody wires the sender, the
///    points arrive and the line comes back by itself.
///  * the events line is unconditional and carries NO number, because there is
///    no period to name. «Пока существует ваш аккаунт» is what is true today;
///    TODO §9.6 records that choosing an actual period is the owner's call, and
///    a period may not be printed here before there is code that deletes.
///
/// The wording is the privacy policy's own (`legal_priv_retention_b`),
/// shortened — the screen must not contradict the document it ships with.
class _RetentionNote extends StatelessWidget {
  /// The server's route window, or null when this day carries no route.
  final int? routeDays;
  const _RetentionNote({required this.routeDays});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    const style =
        TextStyle(fontSize: 12, height: 1.35, color: Ds.textSecondary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_clock_rounded, size: 16, color: Ds.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (routeDays != null) ...[
                Text(l.t('day_retention_route', {'n': routeDays!}), style: style),
                const SizedBox(height: 6),
              ],
              Text(l.t('day_retention_events'), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard();

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('day_empty'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 8),
          // Why it is empty, and what will fill it. «Нет данных» on a screen
          // about a child reads as something being wrong.
          Text(l.t('day_empty_why'), style: const TextStyle(fontSize: 13.5, height: 1.4, color: Ds.textSecondary)),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _FailureCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('day_failed'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: Text(l.t('day_retry'))),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final DayHistory history;
  final String childName;
  final RouteMapBuilder routeMapBuilder;
  final SosOutcomeSaver? onSaveOutcome;

  /// Called after a save succeeds, so the row reflects the new verdict without
  /// refetching the day.
  final void Function(DayEvent event, SosOutcome outcome) onSaved;

  const _Timeline({
    required this.history,
    required this.childName,
    required this.routeMapBuilder,
    required this.onSaveOutcome,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    if (history.events.isEmpty) {
      return Text(
        l.t('sos_no_events'),
        style: const TextStyle(fontSize: 13.5, height: 1.4, color: Ds.textSecondary),
      );
    }
    return Column(
      children: [
        for (final e in history.events)
          _TimelineRow(
            event: e,
            label: _labelFor(l, e),
            // Only an SOS opens a detail screen. A zone crossing has nothing
            // more to say than the line already says, and a row that looks
            // tappable and does nothing is worse than a row that does not.
            onTap: e.kind == DayEventKind.sos
                ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DayEventScreen(
                        childName: childName,
                        event: e,
                        laterEvents: history.events
                            .where((x) => x.at.isAfter(e.at))
                            .toList(),
                        routeMapBuilder: routeMapBuilder,
                        // The whole point of the detail screen. Without these
                        // two the «Чем закончилось» section never appeared and
                        // an alarm could not be closed at all.
                        onSaveOutcome: onSaveOutcome == null
                            ? null
                            : (event, outcome) async {
                                final ok = await onSaveOutcome!(event, outcome);
                                if (ok) onSaved(event, outcome);
                                return ok;
                              },
                        initialOutcome: e.outcome,
                      ),
                    ))
                : null,
          ),
      ],
    );
  }

  static String _labelFor(L10n l, DayEvent e) => switch (e.kind) {
        DayEventKind.sos => l.t('day_sos'),
        // A crossing whose zone has since been deleted still happened. Naming
        // it «зоны null» or dropping it would both be worse than saying that
        // she left a zone.
        DayEventKind.exit => e.zoneName == null
            ? l.t('day_left_unknown')
            : l.t('day_left_zone', {'zone': e.zoneName!}),
        DayEventKind.enter => e.zoneName == null
            ? l.t('day_entered_unknown')
            : l.t('day_entered_zone', {'zone': e.zoneName!}),
      };
}

class _TimelineRow extends StatelessWidget {
  final DayEvent event;
  final String label;
  final VoidCallback? onTap;

  const _TimelineRow({required this.event, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final sos = event.kind == DayEventKind.sos;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(_hhmm(event.at),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ds.textSecondary)),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: sos ? Ds.coralText : Ds.mint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 14.5,
                  color: Ds.text,
                  fontWeight: sos ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded, color: Ds.chevron, size: 20),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
