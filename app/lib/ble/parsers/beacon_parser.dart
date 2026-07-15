/// iBeacon advertisement parser — Dart twin of beaconParser.ts.
/// Pure Dart → unit-testable. Owned by Hardware Integration + Geofencing.
library;

import 'dart:typed_data';
import '../calibration.dart';

const _appleCompanyId = 0x004C;

class BeaconReading {
  final String uuid;
  final int major;
  final int minor;
  final int rssi;
  final int txPower;
  final double distanceM;
  final DateTime observedAt;
  const BeaconReading({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.rssi,
    required this.txPower,
    required this.distanceM,
    required this.observedAt,
  });
}

String _bytesToUuid(Uint8List b) {
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

int _int8(int u) => u > 127 ? u - 256 : u;

/// Parse iBeacon manufacturer data (raw bytes, company-id first two LE bytes).
/// Returns null if it isn't an iBeacon proximity frame (e.g. a Tuya tag).
BeaconReading? parseIBeacon(Uint8List raw, int rssi, DateTime observedAt) {
  if (raw.length < 25) return null;
  final companyId = raw[0] | (raw[1] << 8);
  if (companyId != _appleCompanyId) return null;

  final body = Uint8List.sublistView(raw, 2);
  if (body[0] != 0x02 || body[1] != 0x15) return null;

  final uuid = _bytesToUuid(Uint8List.sublistView(body, 2, 18));
  final major = (body[18] << 8) | body[19];
  final minor = (body[20] << 8) | body[21];
  final txPower = _int8(body[22]);

  return BeaconReading(
    uuid: uuid,
    major: major,
    minor: minor,
    rssi: rssi,
    txPower: txPower,
    distanceM: rssiToDistanceM(rssi, txPower: txPower),
    observedAt: observedAt,
  );
}

/// Median-filter distance to suppress RSSI jitter before it reaches geofencing.
class DistanceSmoother {
  final int window;
  final List<double> _samples = [];
  DistanceSmoother([this.window = 5]);

  double push(double distanceM) {
    if (distanceM < 0) return _median();
    _samples.add(distanceM);
    if (_samples.length > window) _samples.removeAt(0);
    return _median();
  }

  double _median() {
    if (_samples.isEmpty) return -1;
    final s = [..._samples]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }
}
