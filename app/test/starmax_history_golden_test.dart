/// The history parsers, pinned to the VENDOR'S OWN decoder.
///
/// The expectations in this file were not written by hand. Every number in
/// test/fixtures/starmax_history_golden.json came out of
/// docs/sdk-demo/libs/StarmaxSDK/index.js — the JavaScript that ships on
/// handsets talking to these watches — run over the frame bytes recorded
/// alongside them, by app/tool/gen_starmax_history_fixtures.mjs.
///
/// That matters because the alternative is worthless. A parser test whose
/// expected values I typed in from my own reading of a minified vendor bundle
/// proves only that I am consistent with myself; it passes just as happily when
/// I have the offset wrong. Running the vendor's implementation and demanding
/// the same answer is the one form of this test that can fail for the right
/// reason.
///
/// The bytes go in through the same [StarmaxFrameAssembler] and [parseFrame] the
/// radio path uses, split into 20-byte notifications, because reassembly is part
/// of the wire format: a day of heart rate does not fit in one packet.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ble/starmax/starmax_history.dart';
import 'package:fcs_app/ble/starmax/starmax_protocol.dart';

late Map<String, dynamic> _golden;

Map<String, dynamic> _case(String name) {
  final c = (_golden['cases'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((c) => c['name'] == name, orElse: () => throw StateError('no fixture "$name"'));
  return c;
}

List<int> _hex(String s) =>
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

/// Replay a fixture's frames the way the radio delivers them and return the
/// assembled history payload — status byte included, which is where every
/// history parser starts.
List<int> _assemble(String name) {
  final c = _case(name);
  final assembler = StarmaxFrameAssembler();
  final head = <int>[];
  final chunks = <int>[];
  for (final hex in (c['frames'] as List).cast<String>()) {
    final raw = _hex(hex);
    for (var i = 0; i < raw.length; i += 20) {
      final packet = raw.sublist(i, i + 20 > raw.length ? raw.length : i + 20);
      for (final frame in assembler.add(packet)) {
        final f = parseFrame(frame)!;
        expect(f.crcOk, isTrue, reason: 'the fixture frames carry the vendor CRC');
        if (head.isEmpty) head.addAll([f.status, ...f.payload.take(6)]);
        chunks.addAll(f.payload.skip(6));
      }
    }
  }
  return [...head, ...chunks];
}

/// The single-valued payload of a fixture's decoded list, by field name.
List<Map<String, dynamic>> _vendorList(String name, String key) =>
    ((_case(name)['vendor'] as Map)[key] as List).cast<Map<String, dynamic>>();

void main() {
  setUpAll(() {
    final f = File('test/fixtures/starmax_history_golden.json');
    expect(f.existsSync(), isTrue,
        reason: 'run: node tool/gen_starmax_history_fixtures.mjs');
    _golden = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  });

  test('valid history dates decode to the days the vendor found (§5.53)', () {
    final c = _case('validHistoryDates');
    final frame = parseFrame(_hex((c['frames'] as List).first as String))!;
    final ours = parseValidHistoryDates(frame.payload);
    final theirs = ((c['vendor'] as Map)['validHistoryDates'] as List)
        .cast<Map<String, dynamic>>();

    expect(ours.length, theirs.length);
    for (var i = 0; i < ours.length; i++) {
      expect(ours[i].year, theirs[i]['year']);
      expect(ours[i].month, theirs[i]['month']);
      expect(ours[i].day, theirs[i]['day']);
    }
    // Not a formality: this is the call the whole backfill is steered by.
    expect(ours, isNotEmpty);
  });

  test('the valid-dates request carries the command byte, not the enum ordinal', () {
    // index.js maps HistoryType through getHistoryTypeCode() before sending, so
    // asking about step history puts 98 on the wire — not 1. Reading the typed
    // enum in the docs and sending its value is the obvious mistake.
    final f = cmdGetValidHistoryDates(StarmaxHistoryType.step);
    expect(f[1], starmaxValidHistoryDatesCmd);
    expect(f[4], 98);
    expect(cmdGetValidHistoryDates(StarmaxHistoryType.heartRate)[4], 99);
    expect(cmdGetValidHistoryDates(StarmaxHistoryType.bloodSugar)[4], 114);
  });

  test('heart rate: 288 samples across two frames match the vendor exactly', () {
    final series = parseHeartRateHistory(_assemble('heartRate'));
    final theirs = _vendorList('heartRate', 'heartRateList');

    expect(series.header.status, 0);
    expect(series.header.intervalMinutes, (_case('heartRate')['vendor'] as Map)['interval']);
    expect(series.header.dataLength, (_case('heartRate')['vendor'] as Map)['dataLength']);
    expect(series.date, DateTime(2026, 8, 10));
    expect(series.samples.length, theirs.length);
    expect(theirs.length, 288, reason: 'a whole day at five-minute sampling');

    for (var i = 0; i < theirs.length; i++) {
      expect(series.samples[i].value, theirs[i]['heartRateValue'], reason: 'sample $i');
      expect(series.samples[i].hour, theirs[i]['hour'], reason: 'hour of $i');
      expect(series.samples[i].minute, theirs[i]['minute'], reason: 'minute of $i');
    }

    // The 0xFF rule, from the vendor's own output: the watch was off the wrist
    // between 01:00 and 02:30 and those slots decode to 0, not to 255.
    final off = series.samples.where((s) => s.minuteOfDay >= 60 && s.minuteOfDay < 150);
    expect(off, isNotEmpty);
    expect(off.every((s) => s.value == 0), isTrue);
  });

  test('blood oxygen matches the vendor', () {
    final series = parseBloodOxygenHistory(_assemble('bloodOxygen'));
    final theirs = _vendorList('bloodOxygen', 'bloodOxygenList');
    expect(series.samples.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      expect(series.samples[i].value, theirs[i]['bloodOxygen'], reason: 'sample $i');
      expect(series.samples[i].hour, theirs[i]['hour']);
      expect(series.samples[i].minute, theirs[i]['minute']);
    }
  });

  test('blood pressure pairs match the vendor (ss then fz)', () {
    final day = parseBloodPressureHistory(_assemble('bloodPressure'));
    final theirs = _vendorList('bloodPressure', 'bloodPressureList');
    expect(day.samples.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      expect(day.samples[i].systolic, theirs[i]['ss'], reason: 'systolic $i');
      expect(day.samples[i].diastolic, theirs[i]['fz'], reason: 'diastolic $i');
      expect((day.samples[i].minuteOfDay / 60).floor(), theirs[i]['hour']);
    }
    // Systolic first. Swapping the pair would still pass a "both numbers are
    // there" test and would report every reading upside down.
    final real = day.samples.where((s) => s.systolic > 0);
    expect(real, isNotEmpty);
    expect(real.every((s) => s.systolic > s.diastolic), isTrue);
  });

  test('temperature decodes to tenths of a degree, matching the vendor', () {
    final series = parseTempHistory(_assemble('temperature'));
    final theirs = _vendorList('temperature', 'tempList');
    expect(series.samples.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      expect(series.samples[i].value, theirs[i]['temp'], reason: 'sample $i');
    }
    final measured = series.samples.where((s) => s.value > 0);
    expect(measured, isNotEmpty);
    // 36.2–36.8 °C, i.e. the vendor's unit is tenths and not whole degrees.
    expect(measured.every((s) => s.value >= 300 && s.value <= 450), isTrue);
  });

  test('stress matches the vendor', () {
    final series = parseStressHistory(_assemble('stress'));
    final theirs = _vendorList('stress', 'pressureList');
    expect(series.samples.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      expect(series.samples[i].value, theirs[i]['pressure'], reason: 'sample $i');
    }
  });

  test('MET matches the vendor', () {
    final series = parseMetHistory(_assemble('met'));
    final theirs = ((_case('met')['vendor'] as Map)['metList'] as List).cast<int>();
    expect(series.samples.map((s) => s.value).toList(), theirs);
  });

  test('blood sugar matches the vendor', () {
    final series = parseBloodSugarHistory(_assemble('bloodSugar'));
    final theirs = _vendorList('bloodSugar', 'bloodSugarList');
    expect(series.samples.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      expect(series.samples[i].value, theirs[i]['bloodSugar'], reason: 'sample $i');
    }
  });

  test('respiration rate matches the vendor, floored step and all', () {
    final series = parseRespirationHistory(_assemble('respirationRate'));
    final theirs = _vendorList('respirationRate', 'respirationRateList');
    expect(series.samples.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      expect(series.samples[i].value, theirs[i]['respirationRate'], reason: 'sample $i');
      expect(series.samples[i].hour, theirs[i]['hour'], reason: 'hour of $i');
      expect(series.samples[i].minute, theirs[i]['minute'], reason: 'minute of $i');
    }
  });

  test('sleep stages match the vendor, including the nap codes', () {
    final series = parseSleepHistory(_assemble('sleep'));
    final theirs = _vendorList('sleep', 'sleepDataList');
    expect(series.samples.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      expect(series.samples[i].value, theirs[i]['status'], reason: 'sample $i');
    }
    // §5.45: a code above 128 is a nap of the same stage.
    final naps = series.samples.where((s) => s.value > 128);
    expect(naps, isNotEmpty);
    expect(StarmaxSleepStage.stage(naps.first.value), StarmaxSleepStage.light);
    expect(StarmaxSleepStage.isAsleep(naps.first.value), isTrue);
    expect(StarmaxSleepStage.isAsleep(StarmaxSleepStage.awake), isFalse);
    expect(StarmaxSleepStage.isAsleep(0), isFalse);
  });

  test('step records match the vendor: steps, calories and decimetres', () {
    final day = parseStepHistory(_assemble('steps'));
    final theirs = _vendorList('steps', 'stepsList');
    expect(day.steps.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      expect(day.steps[i].steps, theirs[i]['steps'], reason: 'steps $i');
      expect(day.steps[i].kcal, theirs[i]['calorie'], reason: 'calories $i');
      expect(day.steps[i].decimetres, theirs[i]['distance'], reason: 'distance $i');
      expect(day.steps[i].minuteOfDay ~/ 60, theirs[i]['hour']);
    }
    // §5.45 documents step.distance in DECIMETRES. Reporting it as metres would
    // multiply every walk by ten and nothing on screen would look wrong.
    final dm = theirs.fold<int>(0, (a, r) => a + (r['distance'] as int));
    expect(day.totalMetres, dm ~/ 10);
    expect(day.totalSteps, theirs.fold<int>(0, (a, r) => a + (r['steps'] as int)));
  });

  test('a day the watch has no data for is an answer, not a crash', () {
    // The vendor's SDK REJECTS this frame — the fixture records code 4,
    // «数据无效». Ours reads the status and yields an empty day, because a
    // backfill walking a week hits days she did not wear it as a matter of
    // course and an exception per empty day would make normal look broken.
    final c = _case('heartRateNoData');
    expect(((c['vendor'] as Map)['__rejected'] as Map)['code'], 4);

    final frame = parseFrame(_hex((c['frames'] as List).first as String))!;
    expect(frame.status, 4);
    final series = parseHeartRateHistory([frame.status, ...frame.payload]);
    expect(series.header.status, 4);
    expect(series.samples, isEmpty);
  });

  test('the assembler rebuilds a frame split across notifications', () {
    // The reason all of the above works. A day of heart rate is ~300 bytes; the
    // continuation packets carry no 0xDA header, so treating each notification
    // as a frame sees one truncated frame and then garbage.
    final raw = _hex((_case('heartRate')['frames'] as List).first as String);
    expect(raw.length, greaterThan(20));
    final a = StarmaxFrameAssembler();
    final out = <List<int>>[];
    for (var i = 0; i < raw.length; i += 20) {
      out.addAll(a.add(raw.sublist(i, i + 20 > raw.length ? raw.length : i + 20)));
    }
    expect(out.length, 1);
    expect(out.single, raw);
    expect(parseFrame(out.single)!.crcOk, isTrue);
  });

  test('the assembler resynchronises after a dropped notification', () {
    final raw = _hex((_case('bloodOxygen')['frames'] as List).first as String);
    final a = StarmaxFrameAssembler();
    // Fifteen bytes of a frame whose tail the radio dropped, then a whole one.
    // The orphan's length field measures across the seam, so a naive assembler
    // hands out fifteen good bytes glued to the front of the next frame — which
    // still starts with 0xDA and still carries a real command byte. Only the
    // CRC catches it.
    expect(a.add(raw.sublist(0, 15)), isEmpty);
    final out = a.add(raw);
    expect(out.length, 1, reason: 'the wreckage is dropped, the good frame is not');
    expect(out.single, raw);
    expect(parseFrame(out.single)!.crcOk, isTrue);
  });

  test('the assembler never emits a frame whose checksum fails', () {
    final raw = _hex((_case('bloodOxygen')['frames'] as List).first as String);
    final corrupt = [...raw];
    corrupt[10] ^= 0xFF; // flip a payload byte
    expect(StarmaxFrameAssembler().add(corrupt), isEmpty);
  });
}
