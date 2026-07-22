/// Typed decoders for the Starmax reply frames the app consumes.
///
/// PURE Dart → verified by tool/verify_starmax.dart. Each parser takes the
/// payload of a decoded [StarmaxFrame] and reads the exact byte offsets the
/// vendor SDK writes. Offsets and scales are transcribed from
/// docs/sdk-demo/libs/StarmaxSDK; where the vendor left a field's meaning
/// unlabelled (the blood-pressure pair), the comment says so.
library;

import 'starmax_protocol.dart';

/// Reply command bytes (request + 0x80) for the frames we decode.
class StarmaxReply {
  StarmaxReply._();
  static const pair = StarmaxCmd.pair + starmaxReplyBit; // 129
  static const power = StarmaxCmd.getPower + starmaxReplyBit; // 134
  static const version = StarmaxCmd.getVersion + starmaxReplyBit; // 135
  static const healthDetail = StarmaxCmd.healthDetail + starmaxReplyBit; // 141
  static const healthMeasure = StarmaxCmd.healthMeasure + starmaxReplyBit; // 194
}

int _u16(List<int> b, int i) => (b[i] & 0xFF) | ((b[i + 1] & 0xFF) << 8);
int _u32(List<int> b, int i) =>
    (b[i] & 0xFF) | ((b[i + 1] & 0xFF) << 8) | ((b[i + 2] & 0xFF) << 16) | ((b[i + 3] & 0xFF) << 24);

/// The current-health snapshot behind `getHealthDetail` (frame 141).
///
/// Zero in a "current" field means the watch has no fresh reading (it has not
/// measured recently), NOT a real value — a heart rate of 0 is "unknown", to be
/// shown as a dash rather than a number.
class StarmaxHealthSnapshot {
  final int totalSteps;
  final int totalKcal;
  final int totalMeters;
  final int totalSleepMin;
  final int deepSleepMin;
  final int lightSleepMin;

  final int heartRate; // bpm, 0 = unknown
  final int bloodOxygen; // %, 0 = unknown
  final int stress; // "pressure" 0-100, 0 = unknown
  final int met;

  /// Blood pressure, from the vendor's `fz` (diastolic) / `ss` (systolic)
  /// fields — confirmed by the official docs. 0 = unknown. Watch-estimated, so
  /// surface only with a clinician's framing, never as a diagnosis.
  final int bpDiastolic; // fz
  final int bpSystolic; // ss

  /// Body temperature in tenths of a degree (365 = 36.5 °C), per the vendor's
  /// "0.1摄氏度" unit. 0 = unknown. Use [tempCelsius].
  final int tempRaw;
  final int bloodSugar;
  final bool isWorn;
  final int breathRate;

  const StarmaxHealthSnapshot({
    required this.totalSteps,
    required this.totalKcal,
    required this.totalMeters,
    required this.totalSleepMin,
    required this.deepSleepMin,
    required this.lightSleepMin,
    required this.heartRate,
    required this.bloodOxygen,
    required this.stress,
    required this.met,
    required this.bpDiastolic,
    required this.bpSystolic,
    required this.tempRaw,
    required this.bloodSugar,
    required this.isWorn,
    required this.breathRate,
  });

  /// Temperature in °C, or null when unknown. The device sends tenths.
  double? get tempCelsius => tempRaw == 0 ? null : tempRaw / 10.0;
}

/// Decode a frame-141 payload. Later firmware appends fields; every one past
/// the base block is length-guarded exactly as the vendor SDK guards it, so an
/// older watch that sends a shorter payload parses without throwing.
StarmaxHealthSnapshot parseHealthDetail(List<int> e) {
  return StarmaxHealthSnapshot(
    totalSteps: _u32(e, 0),
    totalKcal: _u32(e, 4),
    totalMeters: _u32(e, 8),
    totalSleepMin: _u16(e, 12),
    deepSleepMin: _u16(e, 14),
    lightSleepMin: _u16(e, 16),
    heartRate: e[18] & 0xFF,
    bpDiastolic: e[19] & 0xFF,
    bpSystolic: e[20] & 0xFF,
    bloodOxygen: e[21] & 0xFF,
    stress: e[22] & 0xFF,
    met: e[23] & 0xFF,
    tempRaw: e.length >= 27 ? _u16(e, 25) : 0,
    bloodSugar: e.length >= 28 ? e[27] & 0xFF : 0,
    // isWear: 1 = worn; 0 = off-wrist; 255/-1 = invalid. Only 1 is "worn".
    isWorn: e.length >= 29 && (e[28] & 0xFF) == 1,
    breathRate: e.length >= 30 ? e[29] & 0xFF : 0,
  );
}

/// A single on-demand measurement result (frame 194).
class StarmaxMeasureResult {
  /// The vendor's reply type byte: 102 = stress ("pressure"), otherwise a heart
  /// rate reading. Kept raw so the caller maps it.
  final int typeByte;
  final int value;
  const StarmaxMeasureResult({required this.typeByte, required this.value});

  bool get isStress => typeByte == 102;
}

StarmaxMeasureResult parseHealthMeasure(List<int> e) =>
    StarmaxMeasureResult(typeByte: e[0] & 0xFF, value: e.length > 1 ? e[1] & 0xFF : 0);

/// Battery state (frame 134): the top bit is "charging", the low 7 bits the
/// percentage.
class StarmaxPower {
  final int percent;
  final bool charging;
  const StarmaxPower({required this.percent, required this.charging});
}

StarmaxPower parsePower(List<int> e) {
  final b = e[0] & 0xFF;
  return StarmaxPower(percent: b & 0x7F, charging: (b >> 7) == 1);
}

/// Firmware/hardware identity (frame 135) — enough to know what is connected.
class StarmaxVersion {
  final String firmware; // "v1.2.3"
  final String model;
  const StarmaxVersion({required this.firmware, required this.model});
}

StarmaxVersion parseVersion(List<int> e) {
  final fw = 'v${e[0]}.${e[1]}.${e[2]}';
  // Model is an ASCII run at offset 13, vendor takes 15 bytes and drops zeros.
  final modelBytes = e.length > 13 ? e.sublist(13, e.length > 28 ? 28 : e.length) : <int>[];
  final model = String.fromCharCodes(modelBytes.where((c) => c > 0));
  return StarmaxVersion(firmware: fw, model: model);
}

/// The pairing handshake reply (frame 129): a status byte, 0 = paired.
int parsePairStatus(List<int> e) => e.isEmpty ? 0 : e[0] & 0xFF;
