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

class StarmaxClient {
  final StarmaxTransport _transport;
  final Duration timeout;

  StreamSubscription<List<int>>? _sub;

  /// Pending requests, keyed by the reply command byte we are waiting for. One
  /// outstanding request per reply-cmd is enough for this device's simple
  /// request/reply cadence.
  final _pending = <int, Completer<StarmaxFrame>>{};

  final _live = StreamController<StarmaxLiveReading>.broadcast();

  /// Live measurement readings (frame 194), for while a measurement is running.
  Stream<StarmaxLiveReading> get liveReadings => _live.stream;

  StarmaxClient(this._transport, {this.timeout = const Duration(seconds: 6)}) {
    _sub = _transport.incoming.listen(_onFrame, onError: (_) {});
  }

  void _onFrame(List<int> bytes) {
    final frame = parseFrame(bytes);
    if (frame == null) return; // not ours / too short

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
    await _live.close();
  }
}
