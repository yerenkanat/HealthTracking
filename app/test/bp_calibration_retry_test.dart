/// A blood-pressure calibration must survive a failed push.
///
/// Every other synced type is re-pushed wholesale at startup, so a request that
/// fails heals itself on the next launch. This one cannot be: the app keeps
/// only the OFFSET, and the offset cannot be split back into the cuff and PPG
/// readings the clinician needs. Those raw values lived solely inside one
/// fire-and-forget request.
///
/// So if it failed — and recording a cuff reading is a deliberate act at a
/// clinic or a pharmacy, exactly where the signal is worst, on an app built to
/// work offline — the numbers were gone. The clinician never saw the
/// calibration, a new device restored nothing, and the only way back was
/// another cuff measurement.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 10);

  /// Records what reached the server.
  List<Map<String, Object>> attach(AppController c, {required bool failing}) {
    final sent = <Map<String, Object>>[];
    c.attachBpCalibrationSync(
      upsert: ({
        required int cuffSystolic,
        required int cuffDiastolic,
        required int ppgSystolic,
        required int ppgDiastolic,
        required DateTime at,
      }) async {
        if (failing) throw Exception('offline');
        sent.add({
          'cuffSystolic': cuffSystolic,
          'cuffDiastolic': cuffDiastolic,
          'ppgSystolic': ppgSystolic,
          'ppgDiastolic': ppgDiastolic,
          'at': at,
        });
      },
    );
    return sent;
  }

  bool calibrate(AppController c) => c.calibrateBp(
        cuffSystolic: 118,
        cuffDiastolic: 76,
        ppgSystolic: 124,
        ppgDiastolic: 81,
        at: now,
      );

  test('a successful push reaches the server with the raw readings', () async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    final sent = attach(c, failing: false);

    expect(calibrate(c), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(sent, hasLength(1));
    // The raw cuff and PPG pairs, not the offset — the offset is what the app
    // keeps, and it is not enough for anyone reading this clinically.
    expect(sent.single['cuffSystolic'], 118);
    expect(sent.single['ppgDiastolic'], 81);
  });

  test('a failed push is retried later, with the readings intact', () async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    attach(c, failing: true);

    // She calibrates with no signal. The calibration itself must still succeed:
    // a failed sync must never fail the thing she just did.
    expect(calibrate(c), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(c.bpCalibration, isNotNull);

    // Now the network is back — as it would be on the next launch.
    final sent = attach(c, failing: false);
    await c.flushPendingBpCalibration();

    expect(sent, hasLength(1), reason: 'the held calibration was never re-sent');
    expect(sent.single['cuffSystolic'], 118);
    expect(sent.single['cuffDiastolic'], 76);
    expect(sent.single['ppgSystolic'], 124);
    expect(sent.single['ppgDiastolic'], 81);
    expect(sent.single['at'], now);
  });

  test('it is sent once, not on every launch afterwards', () async {
    // The server keeps an append-only history, so a calibration re-sent every
    // time the app opens would fill the clinician's view with copies of one
    // measurement.
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    final sent = attach(c, failing: false);

    expect(calibrate(c), isTrue);
    await Future<void>.delayed(Duration.zero);
    await c.flushPendingBpCalibration();
    await c.flushPendingBpCalibration();

    expect(sent, hasLength(1));
  });

  test('flushing with nothing pending does nothing', () async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    final sent = attach(c, failing: false);

    await c.flushPendingBpCalibration();
    expect(sent, isEmpty);
  });
}
