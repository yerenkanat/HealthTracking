/// Pure-Dart verification of dashboard + tracking derivation logic.
/// `dart run tool/verify_features.dart`
library;

import 'dart:io';
import '../lib/domain/health_series.dart';
import '../lib/domain/child_tracker_state.dart';
import '../lib/core/geofence.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

DateTime _t(int min) => DateTime.utc(2026, 7, 15, 8, min);

void main() {
  // ---- health_series ----
  final samples = [
    HealthSample(at: _t(0), heartRate: 72, spo2: 98, systolic: 118, diastolic: 76, coreTemp: 36.6),
    HealthSample(at: _t(1), heartRate: 74, spo2: 97, systolic: 120, diastolic: 78, coreTemp: 36.7),
    HealthSample(at: _t(2), heartRate: 90, spo2: 94, systolic: 145, diastolic: 92, coreTemp: 37.9),
  ];
  final hr = buildSeries(samples, 'hr');
  _chk('buildSeries hr length 3', hr.length == 3);
  _chk('buildSeries chronological', hr.first.t.isBefore(hr.last.t));
  final missing = buildSeries(
      [HealthSample(at: _t(0), spo2: 98)], 'hr'); // no hr → dropped
  _chk('buildSeries drops nulls', missing.isEmpty);

  final stats = statsFor(hr)!;
  _chk('stats latest=90', stats.latest == 90);
  _chk('stats min=72 max=90', stats.min == 72 && stats.max == 90);
  _chk('stats trend up', stats.trend == Trend.up);

  _chk('danger: systolic 145 in danger', latestInDanger('systolic', statsFor(buildSeries(samples, 'systolic'))));
  _chk('danger: spo2 94 below 95 in danger', latestInDanger('spo2', statsFor(buildSeries(samples, 'spo2'))));
  _chk('danger: hr 90 not in danger', !latestInDanger('hr', stats));

  // downsample: 100 points → <= 10 buckets, endpoints preserved-ish
  final many = [for (var i = 0; i < 100; i++) SeriesPoint(_t(i), 60 + (i % 10).toDouble())];
  final ds = downsampleMean(many, 10);
  _chk('downsample <= 10 points', ds.length <= 10 && ds.isNotEmpty);
  _chk('downsample keeps time order', ds.first.t.isBefore(ds.last.t));
  _chk('downsample no-op when small', downsampleMean(hr, 50).length == hr.length);

  // ---- child_tracker_state ----
  final home = Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100);
  final school = Geofence.circle('school', 'School', const Coordinates(43.25, 76.95), 120);
  final fences = [home, school];
  final now = DateTime.utc(2026, 7, 15, 9, 0, 0);

  _chk('freshness live < 2min', freshnessOf(const Duration(minutes: 1)) == Freshness.live);
  _chk('freshness recent < 15min', freshnessOf(const Duration(minutes: 10)) == Freshness.recent);
  _chk('freshness stale > 15min', freshnessOf(const Duration(minutes: 40)) == Freshness.stale);

  _chk('currentZone Home', currentZone(home.center!, fences) == 'Home');
  _chk('currentZone none when far', currentZone(const Coordinates(43.30, 77.0), fences) == null);
  _chk('distanceFromHome ~0 at home', (distanceFromHomeM(home.center!, fences) ?? 999) < 1);

  // The home zone is created BY THE APP with a localized display name, so a
  // Russian user's is "Дом" and a Kazakh user's is "Үй". This used to match the
  // name against the literal English 'home', which meant distance-from-home was
  // silently null for every user of the app's own default language — and the
  // assertion above passed anyway, because it only ever tested English.
  for (final label in ['Home', 'Дом', 'Үй', 'дом', '  ДОМ  ']) {
    final localized = [Geofence.circle('home', label, home.center!, 100)];
    _chk('a home zone named "$label" still gives a distance',
        distanceFromHomeM(const Coordinates(43.240, 76.890), localized) != null);
  }
  // A zone the user made by hand has no 'home' id, so the name has to carry it.
  _chk('a hand-made zone named "Дом" counts as home',
      distanceFromHomeM(const Coordinates(43.240, 76.890),
          [Geofence.circle('zone-7', 'Дом', home.center!, 100)]) != null);
  // ...but an unrelated zone must not be mistaken for home.
  _chk('a zone named "Школа" is not home',
      distanceFromHomeM(const Coordinates(43.240, 76.890),
          [Geofence.circle('zone-8', 'Школа', home.center!, 100)]) == null);

  // A fix claiming to be from the FUTURE means the clocks disagree, and once
  // they do we cannot know how old it is. "Live" is the word a parent acts on,
  // so it is the one thing we must not say. Small skew is tolerated.
  _chk('a slightly-ahead clock is tolerated',
      freshnessOf(const Duration(minutes: -1)) == Freshness.live);
  _chk('a fix from ten hours in the future is never live',
      freshnessOf(const Duration(hours: -10)) == Freshness.stale);
  _chk('nor from an hour in the future',
      freshnessOf(const Duration(minutes: -60)) == Freshness.stale);

  _chk('formatAgo just now', formatAgo(const Duration(seconds: 10)) == 'just now');
  _chk('formatAgo minutes', formatAgo(const Duration(minutes: 5)) == '5 min ago');
  _chk('formatAgo hours', formatAgo(const Duration(hours: 2)) == '2 h ago');

  // The freshness dot refused to call a future-dated fix live, but the SENTENCE
  // beside it did not go through freshnessOf — every bucket in formatAgo is a
  // less-than test, so a negative age landed in the first one. A fix three
  // hours ahead of us read "delayed — last seen just now": the reassuring
  // phrase, printed at the moment we have no idea where the child is.
  _chk('formatAgo tolerates small skew',
      formatAgo(const Duration(minutes: -1)) == 'just now');
  _chk('formatAgo refuses a future timestamp',
      formatAgo(const Duration(hours: -3)) == null);

  final skewed = deriveChildStatus(
    childName: 'Sultan',
    location: home.center,
    updatedAt: now.add(const Duration(hours: 3)),
    fences: fences,
    now: now,
  );
  _chk('a future-dated fix never reads "just now"',
      !skewed.headline.contains('just now'));
  _chk('a future-dated fix says the clocks disagree',
      skewed.freshness == Freshness.stale && skewed.headline.contains('disagree'));

  // At School, fresh → headline "Sultan is at School"
  final atSchool = deriveChildStatus(
    childName: 'Sultan',
    location: school.center,
    updatedAt: now.subtract(const Duration(minutes: 1)),
    fences: fences,
    now: now,
  );
  _chk('status at school headline', atSchool.headline == 'Sultan is at School' && atSchool.freshness == Freshness.live);

  // Stale fix → headline mentions last seen
  final stale = deriveChildStatus(
    childName: 'Sultan',
    location: home.center,
    updatedAt: now.subtract(const Duration(hours: 3)),
    fences: fences,
    now: now,
  );
  _chk('status stale flagged', stale.freshness == Freshness.stale && stale.headline.contains('last seen'));

  // No fix yet
  final none = deriveChildStatus(
      childName: 'Sultan', location: null, updatedAt: null, fences: fences, now: now);
  _chk('status no-fix waiting', none.headline.contains('Waiting'));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
