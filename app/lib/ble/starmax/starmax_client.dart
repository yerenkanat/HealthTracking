/// The Starmax client — turns the pure wire protocol into typed async calls,
/// over any transport.
///
/// This layer is deliberately free of BLE: it talks to a [StarmaxTransport]
/// interface (write bytes, receive notification frames), so the whole
/// request/reply orchestration is testable with a fake transport and no
/// hardware — see test/starmax_client_test.dart. The concrete BLE transport
/// (flutter_blue_plus over the Nordic UART Service) implements the same
/// interface and is the only piece that needs a device.
///
/// A request writes a frame and completes when the matching reply arrives — a
/// reply whose command is the request's + 0x80. Replies with a bad CRC or a
/// non-zero status are surfaced as errors, never as data.
library;

import 'dart:async';
import 'dart:typed_data';

import 'starmax_frames.dart';
import 'starmax_history.dart';
import 'starmax_history_sync.dart';
import 'starmax_protocol.dart';

/// What the client needs from a connection: a way to send a frame, and a stream
/// of raw notification frames coming back.
abstract class StarmaxTransport {
  Future<void> write(List<int> frame);
  Stream<List<int>> get incoming;
}

/// Raised when a reply does not arrive in time, or the device reports an error
/// status, or a reply fails its checksum.
class StarmaxError implements Exception {
  final String message;
  const StarmaxError(this.message);
  @override
  String toString() => 'StarmaxError: $message';
}

/// A single live measurement reading pushed by the watch during a measurement.
class StarmaxLiveReading {
  final StarmaxMeasureResult result;
  const StarmaxLiveReading(this.result);
}

/// A history transfer in progress: the device answers one day with one or more
/// frames that each repeat the day's header, and the payload is only complete
/// once their sample runs add up to the header's `dataLength`.
class _HistoryWait {
  final Completer<List<int>?> completer = Completer<List<int>?>();
  final List<int> head = []; // status, interval, y, m, d, len16
  final List<int> chunks = [];
  int dataLength = 0;
  Timer? idle;

  void cancelIdle() => idle?.cancel();
}

class StarmaxClient implements StarmaxHistoryReader {
  final StarmaxTransport _transport;
  final Duration timeout;

  /// How long a history transfer may go without a new frame before it is
  /// abandoned. Separate from [timeout] because a day of samples is several
  /// frames and the whole transfer is legitimately slower than a one-frame read;
  /// what must not happen is waiting for ever on a watch that stopped talking.
  final Duration historyIdleTimeout;

  StreamSubscription<List<int>>? _sub;

  /// Reassembles notifications into whole frames. A history reply does not fit
  /// in one, and its continuation packets carry no header.
  final _assembler = StarmaxFrameAssembler();

  /// Pending requests, keyed by the reply command byte we are waiting for. One
  /// outstanding request per reply-cmd is enough for this device's simple
  /// request/reply cadence.
  final _pending = <int, Completer<StarmaxFrame>>{};

  /// Pending multi-frame history transfers, keyed the same way.
  final _history = <int, _HistoryWait>{};

  final _live = StreamController<StarmaxLiveReading>.broadcast();

  /// Live measurement readings (frame 194), for while a measurement is running.
  Stream<StarmaxLiveReading> get liveReadings => _live.stream;

  StarmaxClient(
    this._transport, {
    this.timeout = const Duration(seconds: 6),
    this.historyIdleTimeout = const Duration(seconds: 8),
  }) {
    _sub = _transport.incoming.listen(_onPacket, onError: (_) {});
  }

  void _onPacket(List<int> packet) {
    for (final frame in _assembler.add(packet)) {
      _onFrame(frame);
    }
  }

  void _onFrame(List<int> bytes) {
    final frame = parseFrame(bytes);
    if (frame == null) return; // not ours / too short

    final hist = _history[frame.cmd];
    if (hist != null) {
      _onHistoryFrame(hist, frame);
      return;
    }

    // Live measurement readings arrive unsolicited during a measurement; fan
    // them out rather than completing a request.
    if (frame.cmd == StarmaxReply.healthMeasure && frame.crcOk && frame.status == 0) {
      _live.add(StarmaxLiveReading(parseHealthMeasure(frame.payload)));
      // fall through: a caller may also be awaiting the first 194.
    }

    final waiter = _pending.remove(frame.cmd);
    if (waiter == null || waiter.isCompleted) return;
    if (!frame.crcOk) {
      waiter.completeError(const StarmaxError('checksum mismatch'));
    } else if (frame.status != 0) {
      waiter.completeError(StarmaxError('device status ${frame.status}'));
    } else {
      waiter.complete(frame);
    }
  }

  /// Fold one frame of a history reply into the transfer.
  ///
  /// A history payload is `status, interval, y, m, d, dataLength16` followed by
  /// this frame's slice of the day. Every frame repeats that header; only the
  /// first one's is kept, and the slices are concatenated until they reach
  /// `dataLength`.
  void _onHistoryFrame(_HistoryWait wait, StarmaxFrame frame) {
    if (wait.completer.isCompleted) return;
    if (!frame.crcOk) return; // a corrupt frame is not data; wait for a resend
    final p = frame.payload;
    if (p.length < 6) {
      // Too short to carry a header — the watch is answering something else.
      _finishHistory(frame.cmd, null);
      return;
    }
    if (frame.status != 0) {
      // 4 = 数据无效: the watch holds nothing for this day. That is an answer,
      // not a failure — a wearer who did not wear it on Tuesday has no Tuesday.
      _finishHistory(frame.cmd, null);
      return;
    }
    if (wait.head.isEmpty) {
      wait.head.addAll([frame.status, ...p.take(6)]);
      wait.dataLength = (p[4] & 0xFF) | ((p[5] & 0xFF) << 8);
    }
    wait.chunks.addAll(p.skip(6));
    if (wait.dataLength == 0 || wait.chunks.length >= wait.dataLength) {
      _finishHistory(frame.cmd, [...wait.head, ...wait.chunks]);
      return;
    }
    // More to come: restart the idle clock rather than the whole-transfer one.
    wait.cancelIdle();
    wait.idle = Timer(historyIdleTimeout, () => _finishHistory(frame.cmd, null));
  }

  void _finishHistory(int replyCmd, List<int>? payload) {
    final wait = _history.remove(replyCmd);
    if (wait == null) return;
    wait.cancelIdle();
    if (!wait.completer.isCompleted) wait.completer.complete(payload);
  }

  /// Write a history request and collect every frame of its reply.
  ///
  /// Returns the assembled payload, or null when the watch has nothing for that
  /// day (or went quiet). Never throws for "no data": a sync that walks a week
  /// hits empty days as a matter of course, and an exception per empty day would
  /// make the normal case look like a fault.
  Future<List<int>?> _requestHistory(Uint8List frame, int replyCmd) async {
    _finishHistory(replyCmd, null); // a newer request supersedes an older one
    final wait = _HistoryWait();
    _history[replyCmd] = wait;
    wait.idle = Timer(historyIdleTimeout, () => _finishHistory(replyCmd, null));
    await _transport.write(frame);
    return wait.completer.future;
  }

  /// Write [frame] and wait for the reply whose command is [replyCmd].
  Future<StarmaxFrame> _request(Uint8List frame, int replyCmd) async {
    // A prior wait on the same reply-cmd is abandoned — the newer request wins.
    _pending.remove(replyCmd)?.completeError(const StarmaxError('superseded'));
    final completer = Completer<StarmaxFrame>();
    _pending[replyCmd] = completer;
    await _transport.write(frame);
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(replyCmd);
      throw const StarmaxError('timed out waiting for reply');
    }
  }

  // ---- Typed calls ----

  /// The pairing handshake. Returns the device's pair status (1 = confirmed).
  Future<int> pair({bool ios = false}) async {
    final f = await _request(cmdPair(ios: ios), StarmaxReply.pair);
    return parsePairStatus(f.payload);
  }

  /// The current health snapshot — heart rate, SpO₂, temperature, steps, sleep.
  Future<StarmaxHealthSnapshot> readHealth() async {
    final f = await _request(cmdGetHealthDetail(), StarmaxReply.healthDetail);
    return parseHealthDetail(f.payload);
  }

  Future<StarmaxPower> readPower() async {
    final f = await _request(cmdGetPower(), StarmaxReply.power);
    return parsePower(f.payload);
  }

  Future<StarmaxVersion> readVersion() async {
    final f = await _request(cmdGetVersion(), StarmaxReply.version);
    return parseVersion(f.payload);
  }

  // ---- Per-day history (§5.44–5.53, §5.58) ----

  /// Which days the watch still holds for [type]. Asked FIRST by a sync, so it
  /// requests days that exist instead of walking a guessed window.
  ///
  /// An empty list means the watch has nothing — which is a real answer for a
  /// device that was just reset, and must not be read as a failure.
  @override
  Future<List<DateTime>> readValidHistoryDates(StarmaxHistoryType type) async {
    try {
      final f = await _request(cmdGetValidHistoryDates(type), starmaxValidHistoryDatesReply);
      return parseValidHistoryDates(f.payload);
    } on StarmaxError {
      return const [];
    }
  }

  /// The raw assembled payload for one day of one stream, or null when the watch
  /// holds nothing for it.
  Future<List<int>?> readHistoryPayload(StarmaxHistoryType type, DateTime day) =>
      _requestHistory(cmdGetDayHistory(type, day), type.reply);

  /// One day of a single-valued stream (heart rate, SpO₂, stress, blood sugar,
  /// sleep stages, respiration rate, MET), decoded.
  @override
  Future<StarmaxDaySeries?> readDaySeries(StarmaxHistoryType type, DateTime day) async {
    final p = await readHistoryPayload(type, day);
    if (p == null) return null;
    return switch (type) {
      StarmaxHistoryType.heartRate => parseHeartRateHistory(p),
      StarmaxHistoryType.bloodOxygen => parseBloodOxygenHistory(p),
      StarmaxHistoryType.stress => parseStressHistory(p),
      StarmaxHistoryType.bloodSugar => parseBloodSugarHistory(p),
      StarmaxHistoryType.sleep => parseSleepHistory(p),
      StarmaxHistoryType.respirationRate => parseRespirationHistory(p),
      StarmaxHistoryType.met => parseMetHistory(p),
      StarmaxHistoryType.temp => parseTempHistory(p),
      // Blood pressure and steps are not single-valued; they have their own
      // calls. Asking for them here is a programming error, not a device one.
      StarmaxHistoryType.bloodPressure ||
      StarmaxHistoryType.step =>
        throw StateError('$type has its own decoder'),
    };
  }

  /// One day of blood pressure (systolic/diastolic pairs).
  @override
  Future<StarmaxBpDay?> readBloodPressureDay(DateTime day) async {
    final p = await readHistoryPayload(StarmaxHistoryType.bloodPressure, day);
    return p == null ? null : parseBloodPressureHistory(p);
  }

  /// One day of step records (and any sleep records the same stream carries).
  @override
  Future<StarmaxStepDay?> readStepDay(DateTime day) async {
    final p = await readHistoryPayload(StarmaxHistoryType.step, day);
    return p == null ? null : parseStepHistory(p);
  }

  /// Start a live measurement of [type]; readings arrive on [liveReadings].
  /// Returns the first reading the device sends.
  Future<StarmaxMeasureResult> startMeasure(StarmaxMeasure type) async {
    final f = await _request(cmdHealthMeasure(type, on: true), StarmaxReply.healthMeasure);
    return parseHealthMeasure(f.payload);
  }

  /// Stop a live measurement. Fire-and-forget: the device does not reliably
  /// reply to the stop, so this does not wait.
  Future<void> stopMeasure(StarmaxMeasure type) =>
      _transport.write(cmdHealthMeasure(type, on: false));

  /// Set the watch clock. The device replies with an empty-payload ack, so this
  /// waits only to confirm the write landed.
  Future<void> setTime(DateTime now) async {
    await _request(cmdSetTime(now), StarmaxCmd.time + starmaxReplyBit);
  }

  /// Set the wearer's profile (drives the watch's own calorie/distance maths).
  Future<void> setUserInfo({
    required bool male,
    required int age,
    required int heightCm,
    required double weightKg,
  }) async {
    await _request(
      cmdSetUserInfo(male: male, age: age, heightCm: heightCm, weightKg: weightKg),
      StarmaxCmd.userInfo + starmaxReplyBit,
    );
  }

  /// The one-time bring-up after a BLE link is established: pair, then set the
  /// clock so timestamps are right. Profile is set separately when known.
  Future<void> connect({bool ios = false, DateTime? now}) async {
    await pair(ios: ios);
    await setTime(now ?? _now());
  }

  DateTime _now() => DateTime.now();

  Future<void> dispose() async {
    await _sub?.cancel();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const StarmaxError('client disposed'));
    }
    _pending.clear();
    for (final w in _history.values) {
      w.cancelIdle();
      if (!w.completer.isCompleted) w.completer.complete(null);
    }
    _history.clear();
    _assembler.reset();
    await _live.close();
  }
}
