/// Per-day HISTORY on the Starmax / RunmeFit watch — the days the wearer was
/// not carrying her phone, or had the app closed.
///
/// PURE Dart → pinned to the vendor's OWN decoder by
/// test/starmax_history_golden_test.dart: every expected value in that test's
/// fixture was produced by running index.js over the same bytes, so a parser
/// that disagrees with the shipping implementation fails rather than passing
/// against numbers I typed in myself.
///
/// WHERE THIS COMES FROM
///
/// docs/UniappSDKDocumentation.md §5.44–5.53 and §5.58 name the commands and
/// document the decoded JSON, but contain no raw frame capture, so the byte
/// offsets here are transcribed from the vendor's shipping implementation,
/// docs/sdk-demo/libs/StarmaxSDK/index.js. Where the two disagree the code
/// follows index.js — that is what runs on devices — and the comment says so.
///
/// THE SHAPE OF A HISTORY REPLY
///
/// A history reply is a normal frame whose payload begins with a seven-byte
/// header and then the day's samples:
///
///   status, interval, year-2000, month, day, dataLength16, …samples
///
/// `dataLength` counts the samples for the WHOLE day, which is usually more
/// than fits in one frame, so the device sends several frames with the same
/// header and the app concatenates their sample runs until it has `dataLength`
/// bytes. (index.js `notifySync`/`processSyncData`: element 0 is taken from
/// offset 4 — i.e. the whole payload including this header — and every later
/// frame from offset 11, dropping its repeated header. That is the same rule
/// stated the other way round.)
///
/// THE 0xFF RULE
///
/// Every single-byte sample is read as `value % 255`, so the device's 0xFF
/// "nothing measured in this slot" becomes 0 — the same "0 means unknown"
/// convention the live snapshot already uses. This is index.js's arithmetic,
/// kept exactly: a watch on the nightstand must not read as a heart rate of
/// 255, and it must not read as a real 0 either.
library;

import 'dart:typed_data';

import 'starmax_protocol.dart';

/// The history streams the watch can be asked for.
///
/// [typeCode] is the vendor's `HistoryType` enum (types.ts). [cmd] is the
/// request command byte, and the reply is always `cmd + 0x80`.
///
/// NOTE — `getValidHistoryDates` does NOT send the enum value. index.js maps the
/// enum through `getHistoryTypeCode()` and puts the COMMAND byte on the wire, so
/// asking about step history sends 98, not 1. The typed enum in the docs makes
/// the opposite look obvious; it is wrong.
enum StarmaxHistoryType {
  step(1, 98),
  heartRate(2, 99),
  bloodPressure(3, 100),
  bloodOxygen(4, 101),
  stress(5, 102), // the vendor's "pressure" (压力)
  met(6, 103),
  temp(7, 104),
  bloodSugar(9, 114),
  sleep(10, 116),
  respirationRate(11, 120);

  final int typeCode;
  final int cmd;
  const StarmaxHistoryType(this.typeCode, this.cmd);

  /// The reply command byte for this stream.
  int get reply => cmd + starmaxReplyBit;
}

/// The command byte that asks which days the watch still holds (§5.53).
const starmaxValidHistoryDatesCmd = 105;

/// …and the reply it comes back on.
const starmaxValidHistoryDatesReply = starmaxValidHistoryDatesCmd + starmaxReplyBit; // 233

/// «Which days do you still have?» — asked FIRST, so a sync requests the days
/// that exist instead of guessing at a fixed window and burning radio time on
/// days the watch has already rolled off.
Uint8List cmdGetValidHistoryDates(StarmaxHistoryType type) =>
    buildFrame(starmaxValidHistoryDatesCmd, [type.cmd]);

/// Ask for one day of one stream. The payload is (year-2000, month, day).
Uint8List cmdGetDayHistory(StarmaxHistoryType type, DateTime day) =>
    cmdGetHistory(type.cmd, day);

/// Decode a frame-233 payload into the dates the watch holds.
///
/// Three bytes per date, (year-2000, month, day). index.js ignores a payload of
/// one byte or less, which is how "I have nothing" arrives.
List<DateTime> parseValidHistoryDates(List<int> e) {
  final out = <DateTime>[];
  if (e.length <= 1) return out;
  for (var i = 0; i + 2 < e.length; i += 3) {
    final y = 2000 + (e[i] & 0xFF);
    final m = e[i + 1] & 0xFF;
    final d = e[i + 2] & 0xFF;
    // A padding run of zeros is not a date. The vendor builds year 2000-00-00
    // out of it and leaves the caller to notice; we drop it here rather than
    // hand a DateTime(2000, 0, 0) — which Dart silently normalises to November
    // 1999 — to a sync loop.
    if (m < 1 || m > 12 || d < 1 || d > 31) continue;
    out.add(DateTime(y, m, d));
  }
  return out;
}

/// The seven-byte header every history reply payload starts with.
class StarmaxHistoryHeader {
  final int status; // 0 = ok; 4 = 数据无效, the watch holds nothing for this day
  final int intervalMinutes;
  final DateTime date; // the WEARER's local day, as the watch recorded it
  final int dataLength; // sample bytes for the whole day, across all frames

  const StarmaxHistoryHeader({
    required this.status,
    required this.intervalMinutes,
    required this.date,
    required this.dataLength,
  });
}

/// True when [e] is long enough to carry a history header.
bool _hasHeader(List<int> e) => e.length > 1;

StarmaxHistoryHeader _header(List<int> e) => StarmaxHistoryHeader(
      status: e[0] & 0xFF,
      intervalMinutes: e[1] & 0xFF,
      date: DateTime(2000 + (e[2] & 0xFF), e[3] & 0xFF, e[4] & 0xFF),
      dataLength: (e[5] & 0xFF) | ((e[6] & 0xFF) << 8),
    );

/// One sample, with the minute of the day the vendor places it at.
///
/// [minuteOfDay] is a double on purpose. index.js spreads `dataLength` samples
/// across 1440 minutes with a plain division, so a day whose sample count does
/// not divide 1440 lands on fractional minutes; rounding here would silently
/// disagree with the vendor for those firmwares.
class StarmaxSample {
  final double minuteOfDay;
  final int value;
  const StarmaxSample(this.minuteOfDay, this.value);

  int get hour => (minuteOfDay / 60).floor();
  double get minute => minuteOfDay % 60;

  /// The wall-clock instant of this sample on [day], in the wearer's local zone.
  DateTime at(DateTime day) =>
      DateTime(day.year, day.month, day.day).add(Duration(seconds: (minuteOfDay * 60).round()));
}

/// A day of one single-valued stream.
class StarmaxDaySeries {
  final StarmaxHistoryHeader header;
  final List<StarmaxSample> samples;
  const StarmaxDaySeries(this.header, this.samples);

  DateTime get date => header.date;

  /// Samples the watch actually measured — 0 is its "no reading" marker for
  /// every one of these streams (see THE 0xFF RULE above).
  Iterable<int> get measured => samples.map((s) => s.value).where((v) => v > 0);
}

/// Shared body for the one-byte-per-sample streams: heart rate (227), blood
/// oxygen (229), stress (230), blood sugar (242), sleep (244) and respiration
/// rate (248). They differ only in how the minute of day is stepped.
StarmaxDaySeries _parseByteSeries(List<int> e, {required bool floorStep}) {
  if (!_hasHeader(e)) {
    return StarmaxDaySeries(
      StarmaxHistoryHeader(
          status: e.isEmpty ? 0 : e[0] & 0xFF,
          intervalMinutes: 0,
          date: DateTime(2000),
          dataLength: 0),
      const [],
    );
  }
  final h = _header(e);
  final samples = <StarmaxSample>[];
  if (h.status == 0 && h.dataLength > 0) {
    // index.js stops at min(7 + dataLength, payload length) — a frame that was
    // truncated yields the samples it has rather than throwing.
    final end = (7 + h.dataLength) < e.length ? (7 + h.dataLength) : e.length;
    // Respiration rate (248) alone floors the step; every other stream divides
    // straight. Faithful to index.js, which really does differ per stream.
    final step = floorStep ? (1440 / h.dataLength).floorToDouble() : 1440 / h.dataLength;
    for (var i = 7; i < end; i++) {
      samples.add(StarmaxSample((i - 7) * step, (e[i] & 0xFF) % 255));
    }
  }
  return StarmaxDaySeries(h, samples);
}

/// §5.46 heart rate (frame 227).
StarmaxDaySeries parseHeartRateHistory(List<int> e) => _parseByteSeries(e, floorStep: false);

/// §5.48 blood oxygen (frame 229).
StarmaxDaySeries parseBloodOxygenHistory(List<int> e) => _parseByteSeries(e, floorStep: false);

/// §5.49 stress / 压力 (frame 230).
StarmaxDaySeries parseStressHistory(List<int> e) => _parseByteSeries(e, floorStep: false);

/// §5.58 blood sugar (frame 242), in tenths of a mmol/L.
StarmaxDaySeries parseBloodSugarHistory(List<int> e) => _parseByteSeries(e, floorStep: false);

/// Sleep stages (frame 244). Values are [StarmaxSleepStage] codes.
StarmaxDaySeries parseSleepHistory(List<int> e) => _parseByteSeries(e, floorStep: false);

/// Respiration rate (frame 248). The one stream whose minute step is floored.
StarmaxDaySeries parseRespirationHistory(List<int> e) => _parseByteSeries(e, floorStep: true);

/// §5.50 MET (frame 231) — a bare list, with no per-sample clock in the vendor's
/// output. Same slice bounds as the timed streams.
StarmaxDaySeries parseMetHistory(List<int> e) => _parseByteSeries(e, floorStep: false);

/// A blood-pressure pair.
class StarmaxBpSample {
  final double minuteOfDay;
  final int systolic; // the vendor's `ss` (收缩压)
  final int diastolic; // the vendor's `fz` (舒张压)
  const StarmaxBpSample(this.minuteOfDay, this.systolic, this.diastolic);

  DateTime at(DateTime day) =>
      DateTime(day.year, day.month, day.day).add(Duration(seconds: (minuteOfDay * 60).round()));
}

class StarmaxBpDay {
  final StarmaxHistoryHeader header;
  final List<StarmaxBpSample> samples;
  const StarmaxBpDay(this.header, this.samples);
  DateTime get date => header.date;
}

/// §5.47 blood pressure (frame 228). Two bytes per sample, systolic first.
///
/// The minute step divides 2880 by the BYTE count, not by `dataLength` —
/// index.js does exactly that, and for a two-byte sample the two are the same
/// thing said differently (2880 / bytes == 1440 / samples). Kept in the vendor's
/// form so a firmware that pads the frame behaves identically here and there.
StarmaxBpDay parseBloodPressureHistory(List<int> e) {
  if (!_hasHeader(e)) {
    return StarmaxBpDay(
      StarmaxHistoryHeader(
          status: e.isEmpty ? 0 : e[0] & 0xFF,
          intervalMinutes: 0,
          date: DateTime(2000),
          dataLength: 0),
      const [],
    );
  }
  final h = _header(e);
  final out = <StarmaxBpSample>[];
  if (h.status == 0) {
    final bytes = e.length - 7;
    for (var i = 0; i + 1 < bytes; i += 2) {
      final minute = (i ~/ 2) * (2880 / bytes);
      out.add(StarmaxBpSample(minute, (e[7 + i] & 0xFF) % 255, (e[8 + i] & 0xFF) % 255));
    }
  }
  return StarmaxBpDay(h, out);
}

/// §5.51 temperature (frame 232). Two bytes per sample, little-endian tenths of
/// a degree Celsius (365 = 36.5 °C), each byte first put through the same
/// `% 255` no-reading rule.
StarmaxDaySeries parseTempHistory(List<int> e) {
  if (!_hasHeader(e)) {
    return StarmaxDaySeries(
      StarmaxHistoryHeader(
          status: e.isEmpty ? 0 : e[0] & 0xFF,
          intervalMinutes: 0,
          date: DateTime(2000),
          dataLength: 0),
      const [],
    );
  }
  final h = _header(e);
  final out = <StarmaxSample>[];
  if (h.status == 0) {
    final bytes = e.length - 7;
    for (var i = 0; i + 1 < bytes; i += 2) {
      final minute = (i ~/ 2) * (2880 / bytes);
      final lo = (e[7 + i] & 0xFF) % 255;
      final hi = (e[8 + i] & 0xFF) % 255;
      out.add(StarmaxSample(minute, lo | (hi << 8)));
    }
  }
  return StarmaxDaySeries(h, out);
}

/// The vendor's sleep-status codes (§5.45 enum column), shared by the sleep
/// records inside step history and by the sleep stream (frame 244).
///
/// A value above 128 is a NAP of the same stage — 130 is a light-sleep nap —
/// and the doc says to subtract 128.
class StarmaxSleepStage {
  StarmaxSleepStage._();
  static const onset = 1; // 开始入睡
  static const light = 2; // 浅睡
  static const deep = 3; // 深睡
  static const awake = 4; // 清醒
  static const rem = 5; // 快速眼动
  static const napOffset = 128;

  /// The stage a raw code means, with the nap flag taken off.
  static int stage(int raw) => raw > napOffset ? raw - napOffset : raw;

  /// True when [raw] marks time actually spent asleep. Awake and the 0 filler
  /// are not sleep, and counting them is how a sleep card claims eight hours
  /// for a night spent staring at the ceiling.
  static bool isAsleep(int raw) {
    final s = stage(raw);
    return s == onset || s == light || s == deep || s == rem;
  }
}

/// One quarter/hour of walking, as the watch recorded it.
class StarmaxStepRecord {
  final int minuteOfDay;
  final int steps;
  final int kcal;
  final int decimetres; // §5.45 documents step.distance in 分米 (decimetres)
  const StarmaxStepRecord({
    required this.minuteOfDay,
    required this.steps,
    required this.kcal,
    required this.decimetres,
  });
}

/// §5.45 «同步计步睡眠» — one stream carrying BOTH step records and sleep
/// records, told apart by a four-bit type in the top of the first halfword.
class StarmaxStepDay {
  final StarmaxHistoryHeader header;
  final List<StarmaxStepRecord> steps;
  final List<StarmaxSample> sleep; // value = a StarmaxSleepStage code
  const StarmaxStepDay(this.header, this.steps, this.sleep);

  DateTime get date => header.date;

  int get totalSteps => steps.fold(0, (a, r) => a + r.steps);
  int get totalKcal => steps.fold(0, (a, r) => a + r.kcal);

  /// Distance in metres. The device counts decimetres.
  int get totalMetres => steps.fold(0, (a, r) => a + r.decimetres) ~/ 10;
}

/// Decode frame 226. Six bytes per record:
///   halfword: type in bits 12-15, value in bits 0-11
///   halfword: calories
///   halfword: distance (decimetres)
/// The record's clock is its index times the header's `interval`, in minutes —
/// this stream alone uses the interval rather than spreading over 1440.
StarmaxStepDay parseStepHistory(List<int> e) {
  if (!_hasHeader(e)) {
    return StarmaxStepDay(
      StarmaxHistoryHeader(
          status: e.isEmpty ? 0 : e[0] & 0xFF,
          intervalMinutes: 0,
          date: DateTime(2000),
          dataLength: 0),
      const [],
      const [],
    );
  }
  final h = _header(e);
  final steps = <StarmaxStepRecord>[];
  final sleep = <StarmaxSample>[];
  if (h.status == 0) {
    for (var o = 0; o < h.dataLength; o += 6) {
      final i = 7 + o;
      // index.js does not bound this loop; in JavaScript a short frame yields
      // NaN fields, in Dart it would throw. Stopping at the last whole record
      // is the same intent without the crash.
      if (i + 6 > e.length) break;
      final packed = ((e[i + 1] & 0xFF) << 8) + (e[i] & 0xFF);
      final type = packed >> 12;
      final value = packed & 0x0FFF;
      final minute = (o ~/ 6) * h.intervalMinutes;
      if (type == 1) {
        steps.add(StarmaxStepRecord(
          minuteOfDay: minute,
          steps: value,
          kcal: (e[i + 2] & 0xFF) | ((e[i + 3] & 0xFF) << 8),
          decimetres: (e[i + 4] & 0xFF) | ((e[i + 5] & 0xFF) << 8),
        ));
      } else if (type == 2) {
        sleep.add(StarmaxSample(minute.toDouble(), value));
      }
    }
  }
  return StarmaxStepDay(h, steps, sleep);
}
