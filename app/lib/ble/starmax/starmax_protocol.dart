/// The Starmax / RunmeFit smartwatch wire protocol.
///
/// PURE Dart → verified by tool/verify_starmax.dart. No BLE, no I/O: this layer
/// only turns commands into bytes and bytes back into typed frames, so it can
/// be exercised without a device.
///
/// WHERE THIS COMES FROM
///
/// Reversed from the vendor's uniapp SDK (docs/sdk-demo/libs/StarmaxSDK). Their
/// SDK is JavaScript for a Vue framework; this is a faithful re-implementation
/// of the same bytes in Dart, so our Flutter app can talk to the same hardware.
///
/// THE FRAME
///
///   [0xDA, cmd, lenLo, lenHi, ...payload, crcLo, crcHi]
///
///   * 0xDA — the fixed protocol header ("218").
///   * cmd — the command byte. A device REPLY uses the request's cmd + 0x80.
///   * len — payload length, little-endian 16-bit.
///   * crc — CRC-16/ARC over everything before it, little-endian 16-bit.
///
/// A reply frame carries one extra byte the request does not: a status byte at
/// index 4 (0 = ok), with the payload following at index 5.
///
/// The transport is the Nordic UART Service (6E400001-…): write frames to the
/// write characteristic (…0002), receive replies as notifications on the notify
/// characteristic (…0003). Scan filter: advertising data contains 0x00 0x01.
library;

import 'dart:typed_data';

/// The service the watch exposes (Nordic UART Service). Discovery filters on
/// the 16-bit-ish prefix because vendors vary the full 128-bit string.
const starmaxServicePrefix = '6e400001';

/// The two bytes every Starmax device includes in its advertising payload —
/// the scan filter that tells one apart from every other BLE device nearby.
const starmaxAdvMarker = [0x00, 0x01];

/// The fixed frame header.
const starmaxHeader = 0xDA;

/// A reply's command byte is the request's plus this.
const starmaxReplyBit = 0x80;

/// Command bytes (the request side). Names mirror the vendor SDK.
class StarmaxCmd {
  StarmaxCmd._();
  static const pair = 1;
  static const getState = 2;
  static const findPhone = 3;
  static const getPower = 6;
  static const getVersion = 7;
  static const time = 8; // set (with payload) / get (empty)
  static const userInfo = 9; // set / get
  static const healthDetail = 13; // current snapshot → reply 141
  static const healthOpen = 14; // which continuous measurements are on
  static const reset = 15;
  static const closeDevice = 16;
  static const healthMeasure = 66; // start/stop a live measurement → reply 194
  static const stepHistory = 98;
  static const heartRateHistory = 99;
  static const bloodOxygenHistory = 101;
  static const tempHistory = 104;
  static const sleepHistory = 116;
}

/// The kinds of on-demand measurement `healthMeasure` can start.
///
/// TWO, not seven. These are the vendor's `HealthMeasureType` (types.ts) and the
/// docs pin them explicitly — §5.39's field table reads «healthType … (99)：心率
/// (102)：压力». The reply parser agrees: index.js frame 194 tests `e[0] == 102`
/// for stress and calls everything else a heart rate.
///
/// This enum previously carried heartRate(1) … respiratoryRate(7). Those are the
/// values of a DIFFERENT enum — `HealthIntervalType` from §5.63, which says how
/// often the watch should sample a metric in the background. Sent as a measure
/// type they name nothing the firmware recognises, so `startMeasure` was asking
/// the watch for a measurement it has no way to start. Nothing outside a test
/// ever called it, so nothing surfaced.
enum StarmaxMeasure {
  heartRate(99),
  stress(102);

  final int code;
  const StarmaxMeasure(this.code);
}

/// CRC-16/ARC (reflected, polynomial 0xA001, init 0x0000, no final xor) — the
/// checksum the vendor SDK appends. Generated rather than transcribed so the
/// 256-entry table can't be copied wrong; the runner pins it to the standard
/// "123456789" → 0xBB3D check value.
final Uint16List _crcTable = _buildCrcTable();

Uint16List _buildCrcTable() {
  final table = Uint16List(256);
  for (var i = 0; i < 256; i++) {
    var crc = i;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
    table[i] = crc & 0xFFFF;
  }
  return table;
}

/// CRC-16/ARC of [bytes], as a 16-bit int.
int starmaxCrc(List<int> bytes) {
  var crc = 0;
  for (final b in bytes) {
    crc = ((crc >> 8) & 0xFF) ^ _crcTable[(crc ^ b) & 0xFF];
  }
  return crc & 0xFFFF;
}

/// Build a complete command frame for [cmd] with [payload].
Uint8List buildFrame(int cmd, [List<int> payload = const []]) {
  final len = payload.length;
  final head = <int>[starmaxHeader, cmd & 0xFF, len & 0xFF, (len >> 8) & 0xFF, ...payload.map((b) => b & 0xFF)];
  final crc = starmaxCrc(head);
  return Uint8List.fromList([...head, crc & 0xFF, (crc >> 8) & 0xFF]);
}

// ---- Command builders (the ones the app needs) ----

/// Pair / handshake. [ios] selects the platform byte the watch expects (1 =
/// Android, 2 = iOS), exactly as the vendor SDK does.
Uint8List cmdPair({required bool ios}) => buildFrame(StarmaxCmd.pair, [ios ? 2 : 1]);

/// Ask for the current health snapshot (reply frame 141).
Uint8List cmdGetHealthDetail() => buildFrame(StarmaxCmd.healthDetail);

Uint8List cmdGetPower() => buildFrame(StarmaxCmd.getPower);
Uint8List cmdGetVersion() => buildFrame(StarmaxCmd.getVersion);

/// Set the watch clock. Payload: year LE16, month, day, hour, minute, second,
/// utc-offset-hours (signed byte), matching the vendor layout.
Uint8List cmdSetTime(DateTime t) {
  final year = t.year;
  final offset = _utcOffsetHours(t);
  return buildFrame(StarmaxCmd.time, [
    year & 0xFF,
    (year >> 8) & 0xFF,
    t.month,
    t.day,
    t.hour,
    t.minute,
    t.second,
    offset & 0xFF,
  ]);
}

/// Set the wearer's profile. Payload: sex (0=female,1=male), age, height LE16
/// in cm, weight LE16 — the numbers the watch uses to compute calories and
/// distance. Weight is sent in TENTHS of a kilo, per the vendor's "0.1 KG"
/// unit, so 60.5 kg → 605.
Uint8List cmdSetUserInfo({
  required bool male,
  required int age,
  required int heightCm,
  required double weightKg,
}) {
  final w = (weightKg * 10).round();
  return buildFrame(StarmaxCmd.userInfo, [
    male ? 1 : 0,
    age & 0xFF,
    heightCm & 0xFF,
    (heightCm >> 8) & 0xFF,
    w & 0xFF,
    (w >> 8) & 0xFF,
  ]);
}

/// Start or stop a live measurement of [type] (reply frames 194).
Uint8List cmdHealthMeasure(StarmaxMeasure type, {required bool on}) =>
    buildFrame(StarmaxCmd.healthMeasure, [type.code, on ? 1 : 0]);

/// Request a day's stored history for a metric. [cmd] is one of the history
/// command bytes; the payload is the date as (year-2000, month, day).
Uint8List cmdGetHistory(int cmd, DateTime day) =>
    buildFrame(cmd, [(day.year - 2000) & 0xFF, day.month, day.day]);

int _utcOffsetHours(DateTime t) {
  // Whole hours east of UTC, signed. The device stores a single byte.
  final minutes = t.timeZoneOffset.inMinutes;
  return (minutes / 60).truncate();
}

/// A decoded frame: header/cmd/status split out, payload isolated, CRC checked.
class StarmaxFrame {
  final int cmd;
  final int status; // 0 = ok on a reply
  final List<int> payload;
  final bool crcOk;

  /// True when this is a device→app reply (cmd has the reply bit).
  bool get isReply => cmd >= starmaxReplyBit;

  /// The request command this replies to (reply bit stripped), or the cmd
  /// itself when it is not a reply.
  int get replyTo => isReply ? cmd - starmaxReplyBit : cmd;

  const StarmaxFrame({
    required this.cmd,
    required this.status,
    required this.payload,
    required this.crcOk,
  });
}

/// Reassembles logical frames out of BLE notifications.
///
/// WHY THIS IS NOT OPTIONAL
///
/// Every frame the app asked for until now fitted in one notification, so the
/// client could parse each packet as a whole frame. A day of heart rate is 288
/// samples: the frame is ~300 bytes and the radio delivers it in whatever the
/// negotiated MTU allows — 20 bytes on a conservative link. The continuation
/// packets do NOT repeat the 0xDA header, so a parser that treats each
/// notification as a frame sees one truncated frame and a stream of garbage.
///
/// The frame's own length field is the authority: total = 4 + len + 2. That is
/// the same rule the vendor applies (index.js counts `length - 13` sample bytes
/// per frame, i.e. minus an 11-byte header and a 2-byte CRC), stated in the form
/// that does not need to know which commands are "sync" commands.
class StarmaxFrameAssembler {
  final List<int> _buf = [];

  /// The most bytes to hold while waiting for the rest of a frame. A day of
  /// samples is a few hundred; anything past this is a desynchronised stream,
  /// not a frame, and holding it for ever would leak.
  static const maxPending = 4096;

  /// Feed one notification; get back the complete logical frames it finished.
  List<List<int>> add(List<int> packet) {
    _buf.addAll(packet);
    final out = <List<int>>[];
    while (true) {
      // Resynchronise: drop anything before a header byte. A packet that starts
      // mid-stream is a dropped notification, not data.
      if (_buf.isNotEmpty && _buf[0] != starmaxHeader) {
        final at = _buf.indexOf(starmaxHeader);
        if (at < 0) {
          _buf.clear();
          break;
        }
        _buf.removeRange(0, at);
      }
      if (_buf.length < 4) break;
      final total = 4 + (_buf[2] | (_buf[3] << 8)) + 2;
      if (total > maxPending) {
        // A length that cannot be real — drop this header and look for the next.
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < total) break;
      final candidate = _buf.sublist(0, total);
      // The CRC is what makes resynchronisation possible. A dropped
      // notification leaves a truncated frame in front of a good one; the
      // length field then measures across the seam and the bytes handed out
      // would be half of one frame and half of the next — with a plausible
      // command byte on the front. Checking here and stepping one byte on
      // failure finds the real header instead of emitting the wreckage.
      final given = candidate[total - 2] | (candidate[total - 1] << 8);
      if (given != starmaxCrc(candidate.sublist(0, total - 2))) {
        _buf.removeAt(0);
        continue;
      }
      out.add(candidate);
      _buf.removeRange(0, total);
    }
    if (_buf.length > maxPending) _buf.clear();
    return out;
  }

  void reset() => _buf.clear();
}

/// Parse a raw notification frame. Returns null when it is too short or the
/// header is wrong — a partial/foreign packet, not ours to decode.
///
/// The CRC is checked but not fatal here (surfaced as [StarmaxFrame.crcOk]) so
/// the caller decides whether to drop it; the vendor SDK rejects on mismatch.
StarmaxFrame? parseFrame(List<int> bytes) {
  if (bytes.length < 7) return null; // header+cmd+len16+status+crc16 minimum
  if (bytes[0] != starmaxHeader) return null;
  final cmd = bytes[1];
  final crcGiven = bytes[bytes.length - 2] | (bytes[bytes.length - 1] << 8);
  final crcCalc = starmaxCrc(bytes.sublist(0, bytes.length - 2));
  // A reply carries a status byte at index 4, payload from index 5.
  final status = bytes[4];
  final payload = bytes.sublist(5, bytes.length - 2);
  return StarmaxFrame(
    cmd: cmd,
    status: status,
    payload: payload,
    crcOk: crcGiven == crcCalc,
  );
}
