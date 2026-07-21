/// The newborn daily log — feeds, diapers, and sleep.
///
/// PURE Dart → verified by tool/verify_newborn_log.dart.
///
/// WHY THIS EXISTS
///
/// The app follows a woman through pregnancy and then, at the birth, hands her a
/// development calendar and a vaccination schedule — both looking WEEKS ahead.
/// Neither helps with the actual first days, which are measured in feeds and
/// nappies and twenty-minute stretches of sleep. A new parent, sleep-deprived
/// and asked at the two-week check "how many wet nappies a day?", genuinely
/// cannot remember. That question has a real clinical purpose — it is how a
/// clinic checks a baby is feeding enough — and the app is well placed to
/// answer it.
///
/// So this is a log of small events with a timestamp, and a rollup of "today".
/// Deliberately not more: no analysis, no norms, no judgement. A tired parent
/// tapping a button at 3am does not need the app to have an opinion.
library;

import 'cycle_log.dart' show dateKey;

/// What was logged.
enum NewbornEventKind {
  /// A feed. [detail] carries the side or "bottle".
  feed,

  /// A nappy change. [detail] carries "wet", "dirty" or "both".
  diaper,

  /// A stretch of sleep. [detail] carries nothing; [durationMin] carries how
  /// long, when it is known.
  sleep,
}

class NewbornEvent {
  final DateTime at;
  final NewbornEventKind kind;

  /// Free-form sub-type, from a small fixed set per kind. Kept as a string
  /// rather than a second enum per kind because it is display-only — the app
  /// never branches on it — and a string keeps the model flat.
  final String? detail;

  /// Sleep length in minutes, when recorded. Null for an untimed nap or a
  /// non-sleep event.
  final int? durationMin;

  const NewbornEvent({
    required this.at,
    required this.kind,
    this.detail,
    this.durationMin,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'kind': kind.name,
        if (detail != null) 'detail': detail,
        if (durationMin != null) 'durationMin': durationMin,
      };

  /// Throws on an unusable row, so the tolerant list parser drops that event
  /// rather than the whole child.
  factory NewbornEvent.fromJson(Map<String, dynamic> j) {
    final kind = NewbornEventKind.values.asNameMap()[j['kind']];
    if (kind == null) throw FormatException('unknown newborn event kind ${j['kind']}');
    final dur = (j['durationMin'] as num?)?.toInt();
    if (dur != null && (dur < 0 || dur > 24 * 60)) {
      throw FormatException('implausible sleep length $dur');
    }
    return NewbornEvent(
      at: DateTime.parse(j['at'] as String),
      kind: kind,
      detail: j['detail'] as String?,
      durationMin: dur,
    );
  }
}

/// Add an event, keeping the list newest-first.
///
/// Newest-first because that is the order the log is read — the last feed is
/// the thing a parent checks. Unlike growth, there is NO per-day dedup: ten
/// feeds a day is normal and each is a real event.
List<NewbornEvent> addNewbornEvent(List<NewbornEvent> events, NewbornEvent e) =>
    [e, ...events]..sort((a, b) => b.at.compareTo(a.at));

/// Remove a specific event by its exact timestamp and kind.
///
/// By (at, kind) rather than identity, so a value reconstructed from storage
/// can still be removed. Two events at the same instant of the same kind is
/// not a case worth complicating this for — a human cannot tap twice in the
/// same microsecond.
List<NewbornEvent> removeNewbornEventFrom(List<NewbornEvent> events, NewbornEvent target) =>
    [for (final e in events) if (!(e.at == target.at && e.kind == target.kind)) e];

/// Events on the same calendar day as [day], newest-first.
List<NewbornEvent> eventsOn(List<NewbornEvent> events, DateTime day) {
  final key = dateKey(day);
  return [for (final e in events) if (dateKey(e.at) == key) e];
}

/// A day's tallies, for the "today" summary.
class NewbornDaySummary {
  final int feeds;
  final int diapers;

  /// Nappies that were wet (wet or both). The clinically interesting count in
  /// the first days.
  final int wetDiapers;
  final int sleepStretches;

  /// Total recorded sleep in minutes. Only counts stretches with a duration —
  /// an untimed nap adds to [sleepStretches] but not to this.
  final int sleepMinutes;

  const NewbornDaySummary({
    required this.feeds,
    required this.diapers,
    required this.wetDiapers,
    required this.sleepStretches,
    required this.sleepMinutes,
  });

  bool get isEmpty => feeds == 0 && diapers == 0 && sleepStretches == 0;
}

/// Roll up [day] from [events].
NewbornDaySummary summaryFor(List<NewbornEvent> events, DateTime day) {
  var feeds = 0, diapers = 0, wet = 0, sleeps = 0, sleepMin = 0;
  for (final e in eventsOn(events, day)) {
    switch (e.kind) {
      case NewbornEventKind.feed:
        feeds++;
      case NewbornEventKind.diaper:
        diapers++;
        if (e.detail == 'wet' || e.detail == 'both') wet++;
      case NewbornEventKind.sleep:
        sleeps++;
        sleepMin += e.durationMin ?? 0;
    }
  }
  return NewbornDaySummary(
    feeds: feeds,
    diapers: diapers,
    wetDiapers: wet,
    sleepStretches: sleeps,
    sleepMinutes: sleepMin,
  );
}

/// The most recent event of [kind], or null if none — for "last feed 40 min
/// ago", the single most-asked question at 3am.
NewbornEvent? lastOfKind(List<NewbornEvent> events, NewbornEventKind kind) {
  for (final e in events) {
    if (e.kind == kind) return e; // events are newest-first
  }
  return null;
}
