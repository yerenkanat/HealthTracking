/// Geofence geometry + anti-jitter hysteresis (run with `dart test`).
library;
import 'package:test/test.dart';
import 'package:fcs_app/core/geofence.dart';

void main() {
  final school = Geofence.circle(
      'school', 'School', const Coordinates(43.238949, 76.889709), 100);
  const far = Coordinates(43.245, 76.9);
  final inside = school.center!;

  group('geometry', () {
    test('center inside, far outside', () {
      expect(checkGeofenceBoundary(inside, school).inside, isTrue);
      expect(checkGeofenceBoundary(far, school).inside, isFalse);
    });
    test('haversine ~111m for 0.001° lat', () {
      final d = haversineM(const Coordinates(43.238949, 76.889709),
          const Coordinates(43.239949, 76.889709));
      expect(d, greaterThan(100));
      expect(d, lessThan(120));
    });
  });

  group('hysteresis: alert once, no flapping', () {
    test('needs 2 confirmations then emits exactly one enter', () {
      final t = GeofenceTracker([school],
          const HysteresisConfig(bufferM: 30, confirmations: 2, maxAccuracyM: 100));
      expect(t.update(far, 10), isEmpty);
      expect(t.update(inside, 10), isEmpty);
      final ev = t.update(inside, 10);
      expect(ev, hasLength(1));
      expect(ev.first.transition, GeofenceTransition.enter);
      expect(t.update(inside, 10), isEmpty); // staying inside must not re-fire
    });
    test('drops low-accuracy fixes', () {
      expect(GeofenceTracker([school]).update(inside, 500), isEmpty);
    });
  });
}
