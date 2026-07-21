/// Verifies that a child standing near a zone boundary does not generate a
/// stream of false "left"/"entered" alerts.
library;

import '../lib/core/geofence.dart';
import '../lib/domain/zone_hysteresis.dart';
import '../lib/domain/geofence_alerts.dart';

int _passed = 0, _failed = 0;

void _chk(String name, bool ok) {
  if (ok) {
    _passed++;
  } else {
    _failed++;
    print('  FAIL: $name');
  }
}

/// Almaty-ish. ~111_320 m per degree of latitude, so metres convert cleanly.
const _lat = 43.238949;
const _lng = 76.889709;
Coordinates _north(double metres, {double? accuracy}) =>
    Coordinates(_lat + metres / 111320.0, _lng, accuracyM: accuracy);

final _school = Geofence.circle('school', 'School', const Coordinates(_lat, _lng), 150);

/// Feed a sequence of fixes through the resolver, returning the zone after each.
List<String?> _run(List<Coordinates> fixes, {String? from}) {
  var zone = from;
  var state = ZoneHysteresisState.idle;
  final out = <String?>[];
  for (final f in fixes) {
    final d = resolveZone(
        prevZone: zone, location: f, fences: [_school], state: state);
    zone = d.zone;
    state = d.state;
    out.add(zone);
  }
  return out;
}

void main() {
  // ---- the bug this exists for ----
  // A child sits still just inside the boundary; GPS noise moves the fix a few
  // metres either side. The old path called this a zone change every time,
  // writing "left School" and "entered School" to the feed and pushing both.
  {
    final jitter = [
      _north(148), _north(152), _north(147), _north(153), _north(149), _north(151),
    ];
    final zones = _run(jitter, from: 'School');
    _chk('noise at the boundary never changes zone',
        zones.every((z) => z == 'School'));

    var alerts = 0;
    String? zone = 'School';
    var state = ZoneHysteresisState.idle;
    for (final f in jitter) {
      final r = alertsForFix(
        prevZone: zone,
        location: f,
        fences: [_school],
        childName: 'Sultan',
        at: DateTime(2026, 7, 21),
        hysteresis: state,
      );
      zone = r.zone;
      state = r.state;
      alerts += r.alerts.length;
    }
    _chk('and raises no alerts at all', alerts == 0);
  }

  // ---- a real departure still fires ----
  {
    // Well clear of the fence, twice, is a departure.
    final zones = _run([_north(400), _north(420)], from: 'School');
    _chk('leaving for real is still detected', zones.last == null);
    _chk('but not on the first fix alone', zones.first == 'School');
  }

  // ---- a real arrival still fires ----
  {
    final zones = _run([_north(0), _north(5)], from: null);
    _chk('arriving is detected', zones.last == 'School');
    _chk('and needs confirming too', zones.first == null);
  }

  // ---- one bad fix in a good run changes nothing ----
  {
    // Inside, inside, one wild fix, inside. The wild one starts a pending
    // change; the next fix must cancel it rather than let it accumulate.
    final zones = _run([_north(0), _north(400), _north(0), _north(0)], from: 'School');
    _chk('a single outlier does not eject the child from the zone',
        zones.every((z) => z == 'School'));
  }

  // ---- alternating outliers must not accumulate into a change ----
  {
    // Every other fix is wild. Counting them as consecutive confirmations
    // would let noise cross the threshold given enough time.
    final zones = _run(
        [_north(0), _north(400), _north(0), _north(400), _north(0), _north(400)],
        from: 'School');
    _chk('alternating noise never confirms a change',
        zones.every((z) => z == 'School'));
  }

  // ---- a fix too vague to act on ----
  {
    // A 500 m error radius cannot say which side of a 150 m fence you are on.
    final zones = _run([
      _north(400, accuracy: 500),
      _north(400, accuracy: 500),
      _north(400, accuracy: 500),
    ], from: 'School');
    _chk('an inaccurate fix cannot move the child', zones.every((z) => z == 'School'));

    // And it must not count towards a pending change either.
    String? zone = 'School';
    var state = ZoneHysteresisState.idle;
    for (final f in [_north(400), _north(400, accuracy: 500)]) {
      final d = resolveZone(prevZone: zone, location: f, fences: [_school], state: state);
      zone = d.zone;
      state = d.state;
    }
    _chk('a vague fix does not confirm a pending change', zone == 'School');

    // Accuracy carried on the coordinate is honoured, not only the argument.
    // These were two separate sources for the same fact, and the caller that
    // set it on the coordinate got no gate at all.
    final d = resolveZone(
      prevZone: 'School',
      location: _north(400, accuracy: 999),
      fences: [_school],
      state: ZoneHysteresisState.idle,
    );
    _chk('accuracy on the coordinate is respected', d.held == 'accuracy');
  }

  // ---- a fence too small to enter ----
  {
    // "Inside" means a buffer deep, so a fence shallower than the buffer could
    // never be entered — the alert was silently impossible. The UI enforces a
    // minimum radius, but an imported backup carries any radius at all.
    final tiny = Geofence.circle('yard', 'Yard', const Coordinates(_lat, _lng), 20);
    String? zone;
    var state = ZoneHysteresisState.idle;
    for (var i = 0; i < 3; i++) {
      final d = resolveZone(
          prevZone: zone, location: const Coordinates(_lat, _lng), fences: [tiny], state: state);
      zone = d.zone;
      state = d.state;
    }
    _chk('a 20m zone can still be entered', zone == 'Yard');

    // Same for a small polygon: the buffer used to be applied at full size
    // regardless of how small the shape was.
    const d = 30 / 111320.0; // ~30 m
    final smallPoly = Geofence.polygon('plot', 'Plot', const [
      Coordinates(_lat - d, _lng - d),
      Coordinates(_lat - d, _lng + d),
      Coordinates(_lat + d, _lng + d),
      Coordinates(_lat + d, _lng - d),
    ]);
    String? pz;
    var ps = ZoneHysteresisState.idle;
    for (var i = 0; i < 3; i++) {
      final dec = resolveZone(
          prevZone: pz, location: const Coordinates(_lat, _lng), fences: [smallPoly], state: ps);
      pz = dec.zone;
      ps = dec.state;
    }
    _chk('a small polygon can still be entered', pz == 'Plot');
  }

  // ---- malformed fences must not decide anything ----
  {
    final broken = Geofence.polygon('b', 'Broken', const []);
    final d = resolveZone(
        prevZone: 'School',
        location: const Coordinates(_lat, _lng),
        fences: [broken, _school],
        state: ZoneHysteresisState.idle);
    _chk('an empty polygon does not claim the child', d.zone == 'School');

    final nan = Geofence.circle('n', 'NaN', const Coordinates(double.nan, double.nan), 100);
    final d2 = resolveZone(
        prevZone: null,
        location: const Coordinates(_lat, _lng),
        fences: [nan],
        state: ZoneHysteresisState.idle);
    _chk('a NaN fence claims nobody', d2.zone == null);
  }

  // ---- no fences at all ----
  {
    final d = resolveZone(
        prevZone: null,
        location: const Coordinates(_lat, _lng),
        fences: const [],
        state: ZoneHysteresisState.idle);
    _chk('no fences means no zone, and no crash', d.zone == null);
  }

  // ---- moving between two adjacent zones ----
  {
    final home = Geofence.circle('home', 'Home', const Coordinates(_lat, _lng), 150);
    final school =
        Geofence.circle('school', 'School', Coordinates(_lat + 500 / 111320.0, _lng), 150);
    String? zone = 'Home';
    var state = ZoneHysteresisState.idle;
    final seen = <String?>[];
    for (final f in [_north(0), _north(250), _north(260), _north(500), _north(505)]) {
      final d = resolveZone(prevZone: zone, location: f, fences: [home, school], state: state);
      zone = d.zone;
      state = d.state;
      seen.add(zone);
    }
    _chk('a real journey home → between → school completes', seen.last == 'School');
    _chk('and passes through "no zone" rather than teleporting', seen.contains(null));
  }

  print('$_passed passed, $_failed failed');
  if (_failed > 0) throw Exception('zone hysteresis verification failed');
}
