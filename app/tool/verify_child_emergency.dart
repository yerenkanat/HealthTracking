/// Pure-Dart verification of the child emergency-info model.
/// `dart run tool/verify_child_emergency.dart`
library;

import 'dart:io';
import '../lib/domain/child_emergency.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  {
    _chk('a blank info is empty', const ChildEmergencyInfo().isEmpty);
    _chk('and has nothing critical', !const ChildEmergencyInfo().hasCritical);
    _chk('whitespace-only is still empty',
        const ChildEmergencyInfo(allergies: '   ', notes: '\n').isEmpty);

    _chk('any filled field makes it non-empty',
        !const ChildEmergencyInfo(bloodType: 'O+').isEmpty);
    _chk('an allergy is critical', const ChildEmergencyInfo(allergies: 'penicillin').hasCritical);
    _chk('a condition is critical', const ChildEmergencyInfo(conditions: 'asthma').hasCritical);
    _chk('a doctor phone alone is not "critical" (not acted on instantly)',
        !const ChildEmergencyInfo(doctorPhone: '112').hasCritical);
  }

  // ---- JSON round-trip ----
  {
    const info = ChildEmergencyInfo(
      bloodType: 'A+',
      allergies: 'peanuts',
      conditions: 'asthma',
      medications: 'inhaler',
      doctorName: 'Dr Aliyeva',
      doctorPhone: '+7 700 000 0000',
      contactName: 'Grandma',
      contactPhone: '+7 700 111 1111',
      notes: 'wears glasses',
    );
    final back = ChildEmergencyInfo.fromJson(info.toJson());
    _chk('blood type round-trips', back.bloodType == 'A+');
    _chk('allergies round-trip', back.allergies == 'peanuts');
    _chk('the doctor round-trips', back.doctorName == 'Dr Aliyeva' && back.doctorPhone == '+7 700 000 0000');
    _chk('the emergency contact round-trips', back.contactName == 'Grandma' && back.contactPhone == '+7 700 111 1111');
    _chk('notes round-trip', back.notes == 'wears glasses');
  }

  {
    // A blank info writes an empty map — no wasted disk.
    _chk('a blank info serialises to an empty map', const ChildEmergencyInfo().toJson().isEmpty);
    // Values are trimmed on write.
    _chk('values are trimmed on write',
        const ChildEmergencyInfo(bloodType: '  B-  ').toJson()['bloodType'] == 'B-');
    // A partial info keeps only what was set.
    final partial = const ChildEmergencyInfo(allergies: 'latex').toJson();
    _chk('a partial info writes only the filled field',
        partial.length == 1 && partial['allergies'] == 'latex');
  }

  {
    // copyWith changes one field, keeps the rest.
    const info = ChildEmergencyInfo(bloodType: 'O+', allergies: 'none');
    final edited = info.copyWith(allergies: 'pollen');
    _chk('copyWith changes the named field', edited.allergies == 'pollen');
    _chk('and keeps the others', edited.bloodType == 'O+');
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
