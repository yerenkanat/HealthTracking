/// Is this advertising device one of our watches?
///
/// PURE Dart (no flutter_blue_plus types) so the rule can be unit-tested without
/// a radio — the scan itself cannot be, which is exactly why the decision it
/// makes must not live inside it.
///
/// The same three signals the vendor's own SDK uses, in the order they cost
/// nothing to check:
///   1. the device advertises the Nordic UART Service it speaks over;
///   2. its advertised name looks like one of the models we sell;
///   3. its manufacturer data carries the vendor's 0x00 0x01 marker.
///
/// Any one is enough. A watch is allowed to advertise sparsely — several
/// firmware builds omit the service UUID from the advertisement and only expose
/// it after connecting — and requiring all three would leave a real device off
/// the pairing list with nothing on screen to explain it.
library;

import 'starmax/starmax_protocol.dart';

/// Advertised-name substrings that identify a Starmax/RunmeFit watch. The
/// vendor's models advertise names like "GTS10".
const starmaxNamePrefixes = <String>['GTS', 'RunmeFit', 'Starmax'];

/// True when [id] is a BLE remote id the platform can reconnect to directly,
/// rather than a serial number printed on a box.
///
/// A paired band reaches the app by two roads. The onboarding scan stores the
/// device's own remote id — a MAC on Android ("AA:BB:CC:DD:EE:FF"), a
/// platform-assigned UUID on iOS — and `BluetoothDevice.fromId` reconnects to
/// that with no scan at all. A serial claimed from the printed code is a
/// warehouse identifier the radio has never heard of; handing it to `fromId`
/// produces a device that can never connect, and the retry loop hides that as
/// "out of range" for ever. When it is not one of ours, scan instead.
bool looksLikeBleRemoteId(String id) {
  final s = id.trim();
  if (s.isEmpty) return false;
  // Android: six colon-separated hex octets.
  if (RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(s)) return true;
  // iOS/macOS: a CoreBluetooth UUID.
  return RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
  ).hasMatch(s);
}

/// True when this advertisement is one of our watches.
///
/// [serviceUuids] are lower-cased 128-bit strings as flutter_blue_plus reports
/// them; only the NUS prefix is compared, because vendors vary the rest of the
/// 128-bit string. [manufacturerData] is keyed by company id, as the platform
/// delivers it, and the company-id bytes are searched too — the marker is
/// written into the raw blob, and which side of the company-id split it lands
/// on differs by platform.
bool looksLikeStarmaxWatch({
  required String name,
  List<String> serviceUuids = const [],
  Map<int, List<int>> manufacturerData = const {},
  List<String> namePrefixes = starmaxNamePrefixes,
}) {
  for (final u in serviceUuids) {
    if (u.toLowerCase().contains(starmaxServicePrefix)) return true;
  }
  final n = name.toLowerCase();
  if (n.isNotEmpty && namePrefixes.any((p) => n.contains(p.toLowerCase()))) {
    return true;
  }
  for (final entry in manufacturerData.entries) {
    final blob = [entry.key & 0xFF, (entry.key >> 8) & 0xFF, ...entry.value];
    for (var i = 0; i + 1 < blob.length; i++) {
      if (blob[i] == starmaxAdvMarker[0] && blob[i + 1] == starmaxAdvMarker[1]) {
        return true;
      }
    }
  }
  return false;
}
