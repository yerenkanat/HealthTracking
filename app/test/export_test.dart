/// Unit tests for the JSON data export.
library;
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/persisted_config.dart';

void main() {
  test('exportJson is pretty, valid, and round-trips durable data', () {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.addAppointment('OB visit', DateTime(2026, 8, 1, 9, 0));
    c.logWeight(DateTime(2026, 7, 15), 65.0);
    c.addWater(DateTime(2026, 7, 15), 3);

    final json = c.exportJson();
    expect(json, contains('\n')); // indented / pretty
    expect(json, contains('OB visit'));
    expect(() => jsonDecode(json), returnsNormally); // valid JSON

    // Leads with backup metadata; the extra keys don't break restore.
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['app'], 'Umay');
    expect(decoded['appVersion'], AppController.appVersion);
    expect(decoded['exportedAt'], DateTime(2026, 7, 15).toIso8601String());

    // Restorable: decoding the export yields the same durable data.
    final cfg = PersistedConfig.decode(json);
    expect(cfg.appointments.single.title, 'OB visit');
    expect(cfg.weights.single.kg, 65.0);
    expect(cfg.waterLog.values.single, 3);

    c.dispose();
  });

  test('empty controller still exports valid JSON', () {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    final json = c.exportJson();
    expect(() => jsonDecode(json), returnsNormally);
    expect(jsonDecode(json), isA<Map<String, dynamic>>());
    c.dispose();
  });

  test('export → import restores the data into a fresh controller', () {
    final a = AppController(now: () => DateTime(2026, 7, 15));
    a.debugMarkOnboarded(); // a real backup comes from a set-up phone
    a.addAppointment('OB visit', DateTime(2026, 8, 1, 9, 0));
    a.logWeight(DateTime(2026, 7, 15), 65.0);
    a.addWater(DateTime(2026, 7, 15), 3);
    final backup = a.exportJson();

    final b = AppController(now: () => DateTime(2026, 7, 15));
    expect(b.appointments, isEmpty);
    final ok = b.importJson(backup);
    expect(ok, isTrue);
    expect(b.appointments.single.title, 'OB visit');
    expect(b.weights.single.kg, 65.0);
    expect(b.waterFor(DateTime(2026, 7, 15)), 3);
    // Taken FROM THE FILE now, not forced. _applyConfig used to end with a
    // hardcoded `_onboarded = true`, which looked harmless because restore()
    // only ever ran on already-onboarded configs — and which quietly meant a
    // reset could not return anyone to first-run.
    expect(b.onboarded, isTrue);

    a.dispose();
    b.dispose();
  });

  test('importing garbage fails and leaves state untouched', () {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.addAppointment('Keep me', DateTime(2026, 8, 1, 9, 0));
    final ok = c.importJson('not json at all');
    expect(ok, isFalse);
    expect(c.appointments.single.title, 'Keep me'); // unchanged
    c.dispose();
  });
}
