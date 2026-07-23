/// The newborn daily log — feeds, diapers, sleep.
///
/// Designed for a specific user in a specific state: a parent in the first
/// weeks, exhausted, one-handed, often in the dark. So the logging controls are
/// large and few, the summary answers "how are we doing today" at a glance, and
/// the recent list answers "when was the last feed" — the 3am question.
///
/// No analysis, no norms. A tired parent tapping a button does not need the app
/// to have an opinion; they need it to remember, so a clinic can ask.
library;

import 'package:flutter/material.dart';

import '../../data/cry_classifier_client.dart';
import '../../data/cry_recorder.dart';
import '../../domain/newborn_log.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import 'cry_insight_screen.dart';
import 'safe_sleep_screen.dart';

/// Base URL of the cry-classifier service (packages/cry-classifier). Defaults to
/// the Android-emulator loopback; override at build with
/// --dart-define=CRY_API_BASE=https://…
const _cryApiBase = String.fromEnvironment('CRY_API_BASE', defaultValue: 'http://10.0.2.2:8000');

/// A sleep length, in the reader's language. Localized because the hour/minute
/// units differ per language — the ui-strings guard rejects a hand-written "h".
String _formatDuration(dynamic l, int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return h == 0 ? l.t('nb_dur_m', {'m': m}) : l.t('nb_dur_hm', {'h': h, 'm': m});
}

class NewbornLogScreen extends StatelessWidget {
  final String childName;
  final List<NewbornEvent> events;
  final DateTime today;

  /// Log a new event. The screen builds the [NewbornEvent] and hands it up.
  final void Function(NewbornEvent event) onLog;

  /// Remove an event (after the caller confirms).
  final void Function(NewbornEvent event) onDelete;

  const NewbornLogScreen({
    super.key,
    required this.childName,
    required this.events,
    required this.today,
    required this.onLog,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final summary = summaryFor(events, today);
    final ml = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(l.t('nb_title')),
        actions: [
          // "Why is baby crying" — record a short clip, get a likely reason.
          IconButton(
            icon: const Icon(Icons.graphic_eq_rounded),
            tooltip: l.t('cry_title'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CryInsightScreen(
                  recorder: RecordCryRecorder(),
                  client: CryClassifierClient(baseUrl: Uri.parse(_cryApiBase)),
                ),
              ),
            ),
          ),
          // Safe-sleep guidance, one tap from where sleep is logged.
          IconButton(
            icon: const Icon(Icons.shield_moon_outlined),
            tooltip: l.t('ss_title'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SafeSleepScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Today at a glance.
          Row(children: [
            Expanded(
                child: _Tally(
                    label: l.t('nb_feeds'),
                    value: '${summary.feeds}',
                    sub: _lastAgo(l, lastOfKind(events, NewbornEventKind.feed)),
                    colour: Palette.rose)),
            const SizedBox(width: 10),
            Expanded(
                child: _Tally(
                    label: l.t('nb_diapers'),
                    value: '${summary.diapers}',
                    sub: summary.diapers == 0 ? '' : l.t('nb_wet_count', {'n': summary.wetDiapers}),
                    colour: Palette.teal)),
            const SizedBox(width: 10),
            Expanded(
                child: _Tally(
                    label: l.t('nb_sleep'),
                    value: _sleepValue(l, summary),
                    sub: '',
                    colour: Palette.violet)),
          ]),
          const SizedBox(height: 18),

          // The three big buttons. Large and few, for a one-handed 3am tap.
          Row(children: [
            Expanded(child: _LogButton(icon: Icons.local_drink_outlined, label: l.t('nb_add_feed'), onTap: () => _logFeed(context))),
            const SizedBox(width: 10),
            Expanded(child: _LogButton(icon: Icons.baby_changing_station_outlined, label: l.t('nb_add_diaper'), onTap: () => _logDiaper(context))),
            const SizedBox(width: 10),
            Expanded(child: _LogButton(icon: Icons.nightlight_outlined, label: l.t('nb_add_sleep'), onTap: () => onLog(NewbornEvent(at: DateTime.now(), kind: NewbornEventKind.sleep)))),
          ]),
          const SizedBox(height: 22),

          // The week at a glance — the check-up numbers, collapsed so it never
          // gets between a tired parent and the log buttons above.
          if (!weekAverages(events, today).isEmpty) ...[
            _WeekRecall(events: events, today: today),
            const SizedBox(height: 12),
          ],

          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(l.t('nb_empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.textDim, height: 1.45)),
            )
          else
            for (final e in events.take(40))
              _EventRow(
                event: e,
                time: ml.formatTimeOfDay(TimeOfDay.fromDateTime(e.at)),
                onDelete: () => onDelete(e),
              ),
        ],
      ),
    );
  }

  String _sleepValue(dynamic l, NewbornDaySummary s) {
    if (s.sleepMinutes == 0) return '${s.sleepStretches}';
    return _formatDuration(l, s.sleepMinutes);
  }

  String _lastAgo(dynamic l, NewbornEvent? e) {
    if (e == null) return '';
    return l.t('nb_last', {'ago': l.ago(today.difference(e.at).abs())});
  }

  Future<void> _logFeed(BuildContext context) async {
    final l = L10nScope.of(context);
    final choice = await _pick(context, l.t('nb_feed'), {
      'left': l.t('nb_left'),
      'right': l.t('nb_right'),
      'bottle': l.t('nb_bottle'),
    });
    if (choice != null) onLog(NewbornEvent(at: DateTime.now(), kind: NewbornEventKind.feed, detail: choice));
  }

  Future<void> _logDiaper(BuildContext context) async {
    final l = L10nScope.of(context);
    final choice = await _pick(context, l.t('nb_diaper'), {
      'wet': l.t('nb_wet'),
      'dirty': l.t('nb_dirty'),
      'both': l.t('nb_both'),
    });
    if (choice != null) onLog(NewbornEvent(at: DateTime.now(), kind: NewbornEventKind.diaper, detail: choice));
  }

  /// A small sheet of large choices. The value keys are stored; the labels are
  /// shown.
  Future<String?> _pick(BuildContext context, String title, Map<String, String> options) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final entry in options.entries)
              ListTile(
                title: Text(entry.value, style: const TextStyle(fontSize: 16)),
                onTap: () => Navigator.pop(ctx, entry.key),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// A number rounded for a parent, not a spreadsheet: whole where it is whole,
/// one decimal otherwise. "1.5 feeds a day" reads true; "1.5000001" does not.
String _avgNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// The last seven days, collapsed. The header carries the two numbers a clinic
/// asks for; expanding shows the per-day shape behind them.
class _WeekRecall extends StatelessWidget {
  final List<NewbornEvent> events;
  final DateTime today;
  const _WeekRecall({required this.events, required this.today});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final avg = weekAverages(events, today);
    final days = recentDays(events, today);
    final ml = MaterialLocalizations.of(context);

    return Theme(
      // ExpansionTile draws its own divider lines; the card already has a
      // border, so silence them.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      // The fill lives on a Material, not a coloured Container: ExpansionTile is
      // a ListTile and paints its ink on the nearest Material, which a coloured
      // DecoratedBox would hide.
      child: Material(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Palette.border),
          ),
          child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: Palette.textDim,
          collapsedIconColor: Palette.textDim,
          title: Text(l.t('nb_week_title'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${l.t('nb_week_feeds_avg', {'n': _avgNum(avg.feedsPerDay)})}   ·   '
              '${l.t('nb_week_wet_avg', {'n': _avgNum(avg.wetDiapersPerDay)})}',
              style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.4),
            ),
          ),
          children: [
            for (final d in days)
              _DayRow(
                label: ml.formatMediumDate(d.day),
                summary: d.summary,
                emptyLabel: l.t('nb_week_none'),
              ),
            const SizedBox(height: 6),
            Text(l.t('nb_week_over', {'n': avg.activeDays}),
                style: const TextStyle(color: Palette.textDim, fontSize: 11)),
          ],
          ),
        ),
      ),
    );
  }
}

/// One day in the week breakdown: a date and its three counts.
class _DayRow extends StatelessWidget {
  final String label;
  final NewbornDaySummary summary;
  final String emptyLabel;
  const _DayRow({required this.label, required this.summary, required this.emptyLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: Palette.textDim)),
          ),
          if (summary.isEmpty)
            Text(emptyLabel,
                style: const TextStyle(fontSize: 12, color: Palette.textDim))
          else ...[
            _Count(icon: Icons.local_drink_outlined, n: summary.feeds, colour: Palette.rose),
            const SizedBox(width: 14),
            _Count(icon: Icons.water_drop_outlined, n: summary.wetDiapers, colour: Palette.teal),
            const SizedBox(width: 14),
            _Count(icon: Icons.nightlight_outlined, n: summary.sleepStretches, colour: Palette.violet),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final IconData icon;
  final int n;
  final Color colour;
  const _Count({required this.icon, required this.n, required this.colour});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colour),
          const SizedBox(width: 4),
          Text('$n',
              style: const TextStyle(
                  fontFamily: 'JetBrainsMono', fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      );
}

class _Tally extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color colour;
  const _Tally({required this.label, required this.value, required this.sub, required this.colour});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontFamily: 'JetBrainsMono', fontSize: 22, fontWeight: FontWeight.w700, color: colour)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.textDim, fontSize: 11)),
            ],
          ],
        ),
      );
}

class _LogButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LogButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Palette.violet.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          // A generous target: this is tapped one-handed, half-asleep.
          child: Container(
            height: 84,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: Palette.violet),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Palette.violet)),
              ],
            ),
          ),
        ),
      );
}

class _EventRow extends StatelessWidget {
  final NewbornEvent event;
  final String time;
  final VoidCallback onDelete;
  const _EventRow({required this.event, required this.time, required this.onDelete});

  IconData get _icon => switch (event.kind) {
        NewbornEventKind.feed => Icons.local_drink_outlined,
        NewbornEventKind.diaper => Icons.baby_changing_station_outlined,
        NewbornEventKind.sleep => Icons.nightlight_outlined,
      };

  String _label(dynamic l) => switch (event.kind) {
        NewbornEventKind.feed => l.t('nb_feed'),
        NewbornEventKind.diaper => l.t('nb_diaper'),
        NewbornEventKind.sleep => l.t('nb_sleep'),
      };

  String _detail(dynamic l) {
    final d = event.detail;
    if (event.kind == NewbornEventKind.feed) {
      return {'left': l.t('nb_left'), 'right': l.t('nb_right'), 'bottle': l.t('nb_bottle')}[d] ?? '';
    }
    if (event.kind == NewbornEventKind.diaper) {
      return {'wet': l.t('nb_wet'), 'dirty': l.t('nb_dirty'), 'both': l.t('nb_both')}[d] ?? '';
    }
    if (event.durationMin != null) {
      return _formatDuration(l, event.durationMin!);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final detail = _detail(l);
    return InkWell(
      onLongPress: onDelete,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Icon(_icon, size: 19, color: Palette.textDim),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detail.isEmpty ? _label(l) : '${_label(l)} · $detail',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Text(time, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
        ]),
      ),
    );
  }
}
