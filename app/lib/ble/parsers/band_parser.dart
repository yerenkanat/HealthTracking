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

  bool get isEmpty =>
      coreTempC == null &&
      skinTempC == null &&
      heartRateBpm == null &&
      spo2Pct == null &&
      systolicMmHg == null &&
      diastolicMmHg == null &&
      duringSleep == null;
}

class ParseResult {
  final BandFrame frame;
  final bool ok;
  final String? reason;
  const ParseResult(this.frame, this.ok, [this.reason]);
}

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
  final p = Uint8List.sublistView(bytes, 4, 4 + payloadLen);

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
      final sys = p[0], dia = p[1];
      if (sys >= 60 && sys <= 260 && dia >= 30 && dia < sys) {
        f.systolicMmHg = sys;
        f.diastolicMmHg = dia;
      }
      break;
    case BandCmd.combinedHealth:
      if (_plausibleHr(p[0])) f.heartRateBpm = p[0];
      if (p[1] >= 50 && p[1] <= 100) f.spo2Pct = p[1];
      if (p[2] >= 60 && p[3] < p[2]) {
        f.systolicMmHg = p[2];
        f.diastolicMmHg = p[3];
      }
      f.duringSleep = p[4] == 1;
      break;
    default:
      return ParseResult(f, false, 'unhandled cmd 0x${cmd.toRadixString(16)}');
  }

  return ParseResult(f, !f.isEmpty);
}

bool _plausibleHr(int hr) => hr >= 20 && hr <= 250;
