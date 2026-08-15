/// «История зон» — a child's zone crossings as the SERVER recorded them.
///
/// The back office has been able to read this since geofencing shipped: an
/// operator on «SOS и зоны» can see where a child crossed a boundary and when.
/// The mother could not — `GET /children/:id/events` had no caller anywhere in
/// `app/lib`. On a product sold on child safety that asymmetry is the defect,
/// and this screen is the app's half of it.
///
/// Three states, not two, for the reason [DayHistoryScreen] gives: an empty
/// history and an unreachable server are different facts that call for opposite
/// responses, and a screen that only knows "have rows / do not" tells a parent
/// that nothing happened when in truth nobody asked.
///
/// No map. These rows carry a time, a zone name and the positioning source —
/// there are no coordinates in them at all, on any path — so the screen SAYS
/// that instead of approximating a pin from the zone's centre.
library;

import 'package:flutter/material.dart';

import '../../domain/zone_crossing.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';

/// Fetches the crossings. Returns them, or THROWS — the screen shows a failure
/// differently from an empty history and cannot tell them apart from a list.
typedef ZoneCrossingLoader = Future<List<ZoneCrossing>> Function();

class ZoneHistoryScreen extends StatefulWidget {
  final String childName;
  final ZoneCrossingLoader load;

  /// How many rows were asked for. When exactly this many come back the screen
  /// says so, because "the last fifty" and "all of them" are different claims
  /// and the second is the one a silent list makes.
  final int limit;

  /// Today, injected so the «Сегодня» heading is testable without waiting for
  /// midnight.
  final DateTime now;

  const ZoneHistoryScreen({
    super.key,
    required this.childName,
    required this.load,
    required this.now,
    this.limit = 50,
  });

  @override
  State<ZoneHistoryScreen> createState() => _ZoneHistoryScreenState();
}

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _ZoneHistoryScreenState extends State<ZoneHistoryScreen> {
  List<ZoneCrossing>? _crossings;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await widget.load();
      if (!mounted) return;
      setState(() {
        _crossings = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        // Cleared rather than left under a failure banner: a stale list beside
        // «не удалось загрузить» reads as "this is what there is".
        _crossings = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final rows = _crossings;

    return Scaffold(
      backgroundColor: Ds.cream,
      appBar: AppBar(
        title: Text(l.t('zonehist_title', {'name': widget.childName})),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // On every state, including the failed one. The list is enter/exit
          // and nothing else, and a parent who reads it as the whole record of
          // her child's day has been misled by omission.
          _Note(icon: Icons.filter_alt_outlined, text: l.t('zonehist_scope')),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            _FailureCard(onRetry: _reload)
          else if (rows == null || rows.isEmpty)
            const _EmptyCard()
          else ...[
            for (final group in groupCrossingsByDay(rows)) ...[
              _DayHeading(day: group.day, now: widget.now),
              const SizedBox(height: 6),
              _CrossingCard(crossings: group.crossings),
              const SizedBox(height: 16),
            ],
            if (rows.length >= widget.limit) ...[
              _Note(
                icon: Icons.more_horiz_rounded,
                text: l.t('zonehist_capped', {'n': rows.length}),
              ),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 8),
          // Printed on every state too. It is a statement about what this data
          // is, which stays true when there is none of it.
          _Note(icon: Icons.location_off_outlined, text: l.t('zonehist_no_coords')),
        ],
      ),
    );
  }
}

/// «Сегодня» for today, the date otherwise. The date is written the way
/// «История дня» writes it, so two history screens do not use two formats.
class _DayHeading extends StatelessWidget {
  final DateTime day;
  final DateTime now;
  const _DayHeading({required this.day, required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    return Text(
      isToday ? l.t('today_title') : _ymd(day),
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: Ds.textSecondary),
    );
  }
}

class _CrossingCard extends StatelessWidget {
  final List<ZoneCrossing> crossings;
  const _CrossingCard({required this.crossings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [for (final c in crossings) _CrossingRow(crossing: c)],
      ),
    );
  }
}

class _CrossingRow extends StatelessWidget {
  final ZoneCrossing crossing;
  const _CrossingRow({required this.crossing});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final entered = crossing.transition == ZoneTransition.entered;
    // Arriving somewhere safe and leaving it are not the same news, and the
    // feed has drawn them apart in mint and amber since it was written. Red is
    // reserved for SOS and is deliberately absent from this screen — nothing
    // here is an emergency.
    final colour = entered ? Ds.mint : Ds.amber;
    final icon = entered ? Icons.login_rounded : Icons.logout_rounded;
    final source = crossing.source;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(_hhmm(crossing.at),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Ds.textSecondary)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(l, crossing),
                  style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: Ds.text),
                ),
                if (source != null) ...[
                  const SizedBox(height: 2),
                  Text(l.t('possrc_$source'),
                      style: const TextStyle(
                          fontSize: 12, color: Ds.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The same sentences «История дня» prints for the same events. Two history
  /// screens describing one crossing in two different ways is how a parent ends
  /// up believing there were two.
  static String _label(L10n l, ZoneCrossing c) => switch (c.transition) {
        ZoneTransition.entered => c.zoneName.isEmpty
            ? l.t('day_entered_unknown')
            : l.t('day_entered_zone', {'zone': c.zoneName}),
        ZoneTransition.left => c.zoneName.isEmpty
            ? l.t('day_left_unknown')
            : l.t('day_left_zone', {'zone': c.zoneName}),
      };
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

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
          Text(l.t('zonehist_empty'),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 8),
          Text(l.t('zonehist_empty_why'),
              style: const TextStyle(
                  fontSize: 13.5, height: 1.4, color: Ds.textSecondary)),
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
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 8),
          // The sentence that keeps this apart from the empty state. Without it
          // a parent reads a dead network as a quiet week.
          Text(l.t('zonehist_failed_why'),
              style: const TextStyle(
                  fontSize: 13.5, height: 1.4, color: Ds.textSecondary)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: Text(l.t('day_retry'))),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Ds.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, height: 1.35, color: Ds.textSecondary)),
          ),
        ],
      );
}
