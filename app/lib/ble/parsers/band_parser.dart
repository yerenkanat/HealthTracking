/// Smart-band GATT payload parser — Dart twin of bandParser.ts.
/// Pure Dart (List<int>/Uint8List) → unit-testable without Flutter.
///
/// PROTOCOL NOTE: DaFit/JYou-style frame envelope (header, cmd, BE length, payload,
/// XOR checksum). Confirm the CMD_* ids + offsets against your OEM SDK doc.
/// Owned by the Hardware Integration specialist.
library;

import 'dart:typed_data';
import '../calibration.dart' as cal;

class BandCmd {
  static const heartRate = 0x15;
  static const spo2 = 0x17;
  static const temperature = 0x24;
  static const bloodPressure = 0x22;
  static const combinedHealth = 0x51;
}

const _headerMagic = {0xCD, 0xAB};

/// Accepts a hex string ("cd1500...") or raw bytes → Uint8List.
Uint8List toBytes(Object input) {
  if (input is Uint8List) return input;
  if (input is List<int>) return Uint8List.fromList(input);
  final clean = (input as String).replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

bool verifyChecksum(Uint8List b) {
  if (b.length < 2) return false;
  var xor = 0;
  for (var i = 0; i < b.length - 1; i++) {
    xor ^= b[i];
  }
  return xor == b[b.length - 1];
}

/// Partial telemetry parsed from one frame; caller merges several into a record.
class BandFrame {
  double? coreTempC;
  double? skinTempC;
  int? heartRateBpm;
  int? spo2Pct;
  int? systolicMmHg;
  int? diastolicMmHg;
  bool? duringSleep;

  /// True when the frame carried no MEASUREMENT.
  ///
  /// duringSleep is deliberately not counted: it is context for the other
  /// values, not a reading in its own right. A combined frame whose every
  /// measurement was rejected as implausible is garbage, and counting its sleep
  /// flag would let that frame through as a successful parse.
  bool get isEmpty =>
      coreTempC == null &&
      skinTempC == null &&
      heartRateBpm == null &&
      spo2Pct == null &&
      systolicMmHg == null &&
      diastolicMmHg == null;
}

class ParseResult {
  final BandFrame frame;
  final bool ok;
  final String? reason;
  const ParseResult(this.frame, this.ok, [this.reason]);
}

/// How many payload bytes a command reads, or null if we don't handle it.
/// Kept beside the switch below so the two can't drift apart.
int? _payloadBytesNeeded(int cmd) => switch (cmd) {
      BandCmd.heartRate => 1,
      BandCmd.spo2 => 1,
      BandCmd.temperature => 2,
      BandCmd.bloodPressure => 2,
      BandCmd.combinedHealth => 5,
      _ => null,
    };

ParseResult parseBandFrame(Object input, {bool validateChecksum = false}) {
  final bytes = toBytes(input);
  final f = BandFrame();
  if (bytes.length < 5) return ParseResult(f, false, 'frame too short');
  if (!_headerMagic.contains(bytes[0])) {
    return ParseResult(f, false, 'bad header 0x${bytes[0].toRadixString(16)}');
  }
  if (validateChecksum && !verifyChecksum(bytes)) {
    return ParseResult(f, false, 'checksum mismatch');
  }

  final cmd = bytes[1];
  final payloadLen = (bytes[2] << 8) | bytes[3];
  // payloadLen is stated BY THE FRAME, so a malformed or truncated one can claim
  // more than it carries. Trusting it made sublistView throw RangeError on data
  // arriving from an external device — parsers must reject, never throw.
  if (4 + payloadLen > bytes.length) {
    return ParseResult(f, false, 'payload length $payloadLen exceeds frame');
  }
  final p = Uint8List.sublistView(bytes, 4, 4 + payloadLen);

  // Each command reads a fixed number of payload bytes; check before indexing.
  final needed = _payloadBytesNeeded(cmd);
  if (needed == null) {
    return ParseResult(f, false, 'unhandled cmd 0x${cmd.toRadixString(16)}');
  }
  if (p.length < needed) {
    return ParseResult(f, false, 'payload too short for cmd 0x${cmd.toRadixString(16)}');
  }

  switch (cmd) {
    case BandCmd.heartRate:
      if (_plausibleHr(p[0])) f.heartRateBpm = p[0];
      break;
    case BandCmd.spo2:
      if (p[0] >= 50 && p[0] <= 100) f.spo2Pct = p[0];
      break;
    case BandCmd.temperature:
      final skin = ((p[0] << 8) | p[1]) / 100.0;
      if (skin >= 20 && skin <= 45) {
        f.skinTempC = double.parse(skin.toStringAsFixed(2));
        f.coreTempC = cal.skinToCoreTempC(skin);
      }
      break;
    case BandCmd.bloodPressure:
      if (_plausibleBp(p[0], p[1])) {
        f.systolicMmHg = p[0];
        f.diastolicMmHg = p[1];
      }
      break;
    case BandCmd.combinedHealth:
      if (_plausibleHr(p[0])) f.heartRateBpm = p[0];
      if (p[1] >= 50 && p[1] <= 100) f.spo2Pct = p[1];
      if (_plausibleBp(p[2], p[3])) {
        f.systolicMmHg = p[2];
        f.diastolicMmHg = p[3];
      }
      f.duringSleep = p[4] == 1;
      break;
    default: // unreachable: _payloadBytesNeeded already rejected unknown cmds
      return ParseResult(f, false, 'unhandled cmd 0x${cmd.toRadixString(16)}');
  }

  return ParseResult(f, !f.isEmpty);
}

bool _plausibleHr(int hr) => hr >= 20 && hr <= 250;

/// Whether a systolic/diastolic pair could have come off a person.
///
/// One check shared by both frame types. They used to disagree — the combined
/// frame skipped the diastolic floor entirely, so the same device reported
/// 120/0 through one command and nothing through the other.
///
/// The pulse-pressure floor is what catches a saturated sensor: a disconnected
/// or faulty reading tends to come back all-bits-set, and 255/254 passed every
/// bound the old checks had while being physiologically impossible. It also
/// mattered clinically — a systolic of 255 is over BP_SYSTOLIC_SEVERE, so a
/// broken sensor could raise a preeclampsia emergency on its own.
bool _plausibleBp(int systolic, int diastolic) =>
    systolic >= 70 &&
    systolic <= 250 &&
    diastolic >= 40 &&
    diastolic <= 150 &&
    systolic - diastolic >= 15;
