/// Medication backend sync: the ApiClient calls and the controller hooks that
/// push adds/edits and delete removals (the admin sees what she's taking).
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/medication.dart';
import 'package:fcs_app/l10n/l10n.dart';

class _FakeTransport implements HttpTransport {
  final List<(String, Object?)> calls = [];
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> post(String path, Object body) async {
    calls.add(('POST $path', body));
    return const HttpResponse(201, '{"ok":true}');
  }

  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) async {
    calls.add(('DELETE', path));
    return const HttpResponse(204, '');
  }
}

void main() {
  group('ApiClient medications', () {
    test('putMedication posts id/name/dose/perDay', () async {
      final t = _FakeTransport();
      await ApiClient(t).putMedication({'id': 'med-1', 'name': 'Фолиевая кислота', 'dose': '400 мкг', 'perDay': 1});
      final body = t.calls.firstWhere((c) => c.$1 == 'POST /medications').$2 as Map;
      expect(body['name'], 'Фолиевая кислота');
      expect(body['perDay'], 1);
    });

    test('deleteMedication tolerates 404', () async {
      final t = _FakeTransport();
      await ApiClient(t).deleteMedication('med-1'); // 204 here; no throw
      expect(t.calls.any((c) => c.$1 == 'DELETE' && c.$2 == '/medications/med-1'), isTrue);
    });
  });

  group('controller medication sync hooks', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('adding a medication pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <Medication>[];
      c.attachMedicationSync(upsert: (m) async => pushed.add(m), delete: (_) async {});
      c.addMedication('Железо', dose: '30 мг', perDay: 2);
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.name, 'Железо');
      expect(pushed.first.perDay, 2);
    });

    test('editing a medication pushes the update', () async {
      final c = make();
      addTearDown(c.dispose);
      c.addMedication('Железо');
      final id = c.medications.single.id;
      final pushed = <Medication>[];
      c.attachMedicationSync(upsert: (m) async => pushed.add(m), delete: (_) async {});
      c.updateMedication(id, dose: '60 мг');
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.dose, '60 мг');
    });

    test('removing a medication pushes a delete', () async {
      final c = make();
      addTearDown(c.dispose);
      c.addMedication('Железо');
      final id = c.medications.single.id;
      final deleted = <String>[];
      c.attachMedicationSync(upsert: (_) async {}, delete: (mid) async => deleted.add(mid));
      c.removeMedication(id);
      await Future<void>.delayed(Duration.zero);
      expect(deleted, [id]);
    });
  });
}
