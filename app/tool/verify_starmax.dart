/// Pure-Dart verification of the Starmax / RunmeFit wire protocol.
/// `dart run tool/verify_starmax.dart`
///
/// This is the layer that will talk to real hardware, so the bytes must be
/// exactly the vendor's. The CRC is pinned to a standard published check value,
/// the frame layout is round-tripped, and the health-snapshot parser is run
/// against a hand-built frame with known field values.
library;

import 'dart:io';
import '../lib/ble/starmax/starmax_protocol.dart';
import '../lib/ble/starmax/starmax_frames.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- CRC-16/ARC ----
  {
    // The universally published CRC-16/ARC check value for "123456789".
    final check = starmaxCrc('123456789'.codeUnits);
    _chk('CRC-16/ARC of "123456789" is 0xBB3D', check == 0xBB3D);
    _chk('CRC of empty input is 0', starmaxCrc(const []) == 0);
    // Determinism.
    _chk('CRC is deterministic', starmaxCrc([1, 2, 3, 4]) == starmaxCrc([1, 2, 3, 4]));
  }

  // ---- Frame layout ----
  {
    final f = buildFrame(StarmaxCmd.healthDetail); // no payload
    _chk('frame starts with the 0xDA header', f[0] == starmaxHeader);
    _chk('second byte is the command', f[1] == StarmaxCmd.healthDetail);
    _chk('length is zero for an empty payload', f[2] == 0 && f[3] == 0);
    _chk('an empty-payload frame is header+cmd+len16+crc16 = 6 bytes', f.length == 6);

    // The trailing two bytes are the CRC over everything before them, LE.
    final crc = starmaxCrc(f.sublist(0, f.length - 2));
    _chk('CRC is appended little-endian',
        f[f.length - 2] == (crc & 0xFF) && f[f.length - 1] == ((crc >> 8) & 0xFF));

    // Payload length is little-endian 16-bit.
    final big = buildFrame(0x50, List<int>.filled(300, 0xAB));
    _chk('payload length is little-endian 16-bit', big[2] == (300 & 0xFF) && big[3] == (300 >> 8));
  }

  // ---- Command builders ----
  {
    _chk('pair (android) carries platform byte 1', cmdPair(ios: false)[4] == 1);
    _chk('pair (ios) carries platform byte 2', cmdPair(ios: true)[4] == 2);

    final hm = cmdHealthMeasure(StarmaxMeasure.bloodOxygen, on: true);
    _chk('health-measure names the metric', hm[4] == StarmaxMeasure.bloodOxygen.code);
    _chk('health-measure carries the on flag', hm[5] == 1);
    _chk('stopping a measurement clears the flag',
        cmdHealthMeasure(StarmaxMeasure.heartRate, on: false)[5] == 0);

    final hist = cmdGetHistory(StarmaxCmd.heartRateHistory, DateTime(2026, 7, 22));
    _chk('history date is (year-2000, month, day)',
        hist[4] == 26 && hist[5] == 7 && hist[6] == 22);

    final ui = cmdSetUserInfo(male: false, age: 30, heightCm: 165, weightKg: 60.5);
    _chk('user-info sex byte: female is 0', ui[4] == 0);
    _chk('user-info carries age', ui[5] == 30);
    _chk('user-info height is little-endian 16-bit', ui[6] == (165 & 0xFF) && ui[7] == (165 >> 8));
    // Weight is sent in tenths of a kilo: 60.5 kg → 605.
    _chk('user-info weight is sent in 0.1 kg units', ui[8] == (605 & 0xFF) && ui[9] == (605 >> 8));
  }

  // ---- Parse round-trip and the reply bit ----
  {
    // A reply frame is the request command + 0x80. Build one for frame 141 with
    // a leading status byte, as the device would.
    final reply = buildFrame(StarmaxReply.healthDetail, [0, 1, 2, 3]);
    final parsed = parseFrame(reply)!;
    _chk('a reply frame parses', parsed.crcOk);
    _chk('the reply bit is recognised', parsed.isReply);
    _chk('replyTo strips the reply bit back to the request cmd',
        parsed.replyTo == StarmaxCmd.healthDetail);
    _chk('status byte is read from index 4', parsed.status == 0);
    _chk('payload follows the status byte', parsed.payload.length == 3 &&
        parsed.payload[0] == 1 && parsed.payload[1] == 2 && parsed.payload[2] == 3);

    // A corrupted CRC is flagged, not silently accepted.
    final bad = [...reply];
    bad[bad.length - 1] ^= 0xFF;
    _chk('a bad CRC is flagged', parseFrame(bad)!.crcOk == false);

    _chk('a too-short frame is rejected', parseFrame([0xDA, 1, 0]) == null);
    _chk('a foreign header is rejected', parseFrame([0x00, 1, 0, 0, 0, 0, 0]) == null);
  }

  // ---- The health snapshot (frame 141) ----
  {
    // Hand-built payload with known values at the vendor's offsets. A leading
    // status byte (0) is prepended so parseFrame isolates the health fields.
    final fields = List<int>.filled(30, 0);
    void u32(int i, int v) {
      fields[i] = v & 0xFF;
      fields[i + 1] = (v >> 8) & 0xFF;
      fields[i + 2] = (v >> 16) & 0xFF;
      fields[i + 3] = (v >> 24) & 0xFF;
    }

    void u16(int i, int v) {
      fields[i] = v & 0xFF;
      fields[i + 1] = (v >> 8) & 0xFF;
    }

    u32(0, 12345); // steps
    u32(4, 500); // kcal
    u32(8, 8000); // metres
    u16(12, 480); // total sleep
    u16(14, 120); // deep
    u16(16, 360); // light
    fields[18] = 72; // HR
    fields[19] = 80; // bp diastolic (fz)
    fields[20] = 120; // bp systolic (ss)
    fields[21] = 98; // SpO2
    fields[22] = 35; // stress
    fields[23] = 5; // met
    u16(25, 365); // temp in tenths = 36.5 °C
    fields[28] = 1; // worn
    fields[29] = 16; // breath rate

    final frame = buildFrame(StarmaxReply.healthDetail, [0, ...fields]);
    final s = parseHealthDetail(parseFrame(frame)!.payload);

    _chk('steps decode', s.totalSteps == 12345);
    _chk('kcal decode', s.totalKcal == 500);
    _chk('metres decode', s.totalMeters == 8000);
    _chk('total sleep minutes decode', s.totalSleepMin == 480);
    _chk('deep/light sleep decode', s.deepSleepMin == 120 && s.lightSleepMin == 360);
    _chk('heart rate decodes', s.heartRate == 72);
    _chk('blood oxygen decodes', s.bloodOxygen == 98);
    _chk('stress decodes', s.stress == 35);
    _chk('the blood-pressure pair decodes', s.bpSystolic == 120 && s.bpDiastolic == 80);
    _chk('temperature decodes to 36.5 °C', s.tempCelsius == 36.5);
    _chk('worn flag decodes', s.isWorn == true);
    _chk('breath rate decodes', s.breathRate == 16);
  }

  // ---- A zeroed snapshot reads as "unknown", not as real zeros ----
  {
    final frame = buildFrame(StarmaxReply.healthDetail, [0, ...List<int>.filled(30, 0)]);
    final s = parseHealthDetail(parseFrame(frame)!.payload);
    _chk('an unmeasured heart rate is 0 (to be shown as a dash)', s.heartRate == 0);
    _chk('an unmeasured temperature is null, not 0.0 °C', s.tempCelsius == null);
  }

  // ---- Power, version, measurement ----
  {
    final p = parsePower(parseFrame(buildFrame(StarmaxReply.power, [0, 0x80 | 85]))!.payload);
    _chk('battery percent decodes', p.percent == 85);
    _chk('charging bit decodes', p.charging == true);
    final p2 = parsePower(parseFrame(buildFrame(StarmaxReply.power, [0, 42]))!.payload);
    _chk('not charging decodes', p2.charging == false && p2.percent == 42);

    // Version: v1.2.3, model "GTS10" at offset 13.
    final vf = List<int>.filled(28, 0);
    vf[0] = 1;
    vf[1] = 2;
    vf[2] = 3;
    'GTS10'.codeUnits.asMap().forEach((i, c) => vf[13 + i] = c);
    final v = parseVersion(parseFrame(buildFrame(StarmaxReply.version, [0, ...vf]))!.payload);
    _chk('firmware version decodes', v.firmware == 'v1.2.3');
    _chk('model string decodes', v.model == 'GTS10');

    final m = parseHealthMeasure(parseFrame(buildFrame(StarmaxReply.healthMeasure, [0, 99, 71]))!.payload);
    _chk('a live measurement value decodes', m.value == 71);
    _chk('stress vs heart-rate type byte is exposed', m.isStress == false);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
