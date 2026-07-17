/// Unit tests for the JSON data export.
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
}
