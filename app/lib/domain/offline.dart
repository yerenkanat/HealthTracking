/// Screen 20 — «Офлайн».
///
/// «янтарная плашка «Нет интернета» → плашка «Данные от 14:32 · 26 минут
/// назад» → карта в grayscale с пином dashed → нижний лист «Что можно сделать»
/// + «Обновить».»
///
/// The screen exists because of one sentence a parent says to herself: «она
/// дома» — read off a map that has not been updated for half an hour. The map
/// looked exactly the same as it does when the position is a minute old.
///
/// So the design is about REFUSING to look live: the colour comes out of the
/// map, the pin stops being a solid dot, and the age is stated in words rather
/// than implied by a timestamp nobody reads. What is on screen is still worth
/// showing — it is the last thing we know — but it must not be mistaken for
/// what is happening now.
library;

/// What still works with no connection, so the sheet can say so rather than
/// leaving her guessing which parts of the app are broken.
///
/// Each is something she might actually reach for in the next minute. «Все
/// данные сохранятся» is not on this list: it is true, and it answers a
/// question nobody asks while looking for a child.
enum OfflineAction {
  /// The tracker's own SOS still works — it is on the child's wrist and does
  /// not go through this phone. The most important line on the sheet.
  childSosStillWorks,

  /// Calling the number saved on the child's card. A phone call is not the
  /// internet.
  callSavedNumber,

  /// Anything already downloaded: the calendars, the vaccination schedule,
  /// the diary.
  readSavedContent,

  /// Writing things down. It syncs when the connection returns.
  logOffline,
}

/// The four, in the order they are worth reading. Ordered deliberately: what
/// still protects the child, then how to reach somebody, then what she can
/// still do with the app.
const offlineActions = <OfflineAction>[
  OfflineAction.childSosStillWorks,
  OfflineAction.callSavedNumber,
  OfflineAction.readSavedContent,
  OfflineAction.logOffline,
];

extension OfflineActionKeys on OfflineAction {
  String get l10nKey => switch (this) {
        OfflineAction.childSosStillWorks => 'off_act_sos',
        OfflineAction.callSavedNumber => 'off_act_call',
        OfflineAction.readSavedContent => 'off_act_read',
        OfflineAction.logOffline => 'off_act_log',
      };
}

/// How old the data on screen is, as a pair the UI can render: the clock time
/// it was taken, and how long ago that was.
class DataAge {
  /// Local wall-clock of the reading — «14:32».
  final DateTime at;

  /// Whole minutes since. Never negative: a fix stamped in the future means
  /// the clocks disagree, and «−3 минуты назад» is nonsense on a screen whose
  /// whole job is to be believed.
  final int minutesAgo;

  const DataAge({required this.at, required this.minutesAgo});

  /// Older than an hour, where minutes stop being the useful unit.
  bool get overAnHour => minutesAgo >= 60;

  int get hoursAgo => minutesAgo ~/ 60;
}

DataAge? dataAge(DateTime? at, DateTime now) {
  if (at == null) return null;
  final mins = now.difference(at).inMinutes;
  return DataAge(at: at, minutesAgo: mins < 0 ? 0 : mins);
}

/// Should the map refuse to look live?
///
/// True when there is no connection OR the last fix is old enough that we
/// cannot claim it is current. The two are separate causes with the same
/// consequence, and treating only the first would leave a phone with four bars
/// and a tracker that stopped reporting an hour ago drawing a confident pin.
bool mapShouldLookStale({required bool offline, required Duration? sinceLastFix}) {
  if (offline) return true;
  if (sinceLastFix == null) return true;
  return sinceLastFix > const Duration(minutes: 15);
}
