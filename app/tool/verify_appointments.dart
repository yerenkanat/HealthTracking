/// Pure-Dart verification of the appointments/reminders domain.
/// `dart run tool/verify_appointments.dart`
library;

import 'dart:io';
import '../lib/domain/appointment.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final now = DateTime(2026, 7, 15, 10, 0);
  final all = [
    Appointment(id: 'a', title: 'Ultrasound', at: DateTime(2026, 7, 20, 9, 0)),
    Appointment(id: 'b', title: 'Bloodwork', at: DateTime(2026, 7, 10, 8, 0)), // past
    Appointment(id: 'c', title: 'OB visit', at: DateTime(2026, 7, 16, 15, 30)),
    Appointment(id: 'd', title: 'Old scan', at: DateTime(2026, 6, 1, 12, 0)), // past
  ];

  final split = splitAppointments(all, now);
  _chk('upcoming count', split.upcoming.length == 2);
  _chk('past count', split.past.length == 2);
  _chk('upcoming soonest-first', split.upcoming.first.id == 'c' && split.upcoming.last.id == 'a');
  _chk('past most-recent-first', split.past.first.id == 'b' && split.past.last.id == 'd');

  _chk('next is soonest upcoming', nextAppointment(all, now)?.id == 'c');
  _chk('no next when all past', nextAppointment([all[1], all[3]], now) == null);

  _chk('daysUntil future', daysUntil(all[0], now) == 5);
  _chk('daysUntil tomorrow', daysUntil(all[2], now) == 1);
  _chk('daysUntil past negative', daysUntil(all[1], now) == -5);

  // A same-minute appointment counts as upcoming (not past).
  final atNow = Appointment(id: 'e', title: 'Now', at: now);
  _chk('now counts as upcoming', splitAppointments([atNow], now).upcoming.length == 1);

  // Countdown buckets.
  _chk('when today (0)', appointmentWhen(0) == ApptWhen.today);
  _chk('when today (past)', appointmentWhen(-3) == ApptWhen.today);
  _chk('when tomorrow', appointmentWhen(1) == ApptWhen.tomorrow);
  _chk('when soon (<=7)', appointmentWhen(5) == ApptWhen.soon && appointmentWhen(7) == ApptWhen.soon);
  _chk('when later (>7)', appointmentWhen(8) == ApptWhen.later);

  // JSON round-trip (with + without a note).
  final withNote = Appointment(id: 'x', title: 'Scan', at: DateTime(2026, 8, 1, 9, 15), note: 'Bring papers');
  final rt = Appointment.fromJson(withNote.toJson());
  _chk('round-trip fields', rt.id == 'x' && rt.title == 'Scan' && rt.at == DateTime(2026, 8, 1, 9, 15) && rt.note == 'Bring papers');
  final noNote = Appointment(id: 'y', title: 'Visit', at: DateTime(2026, 8, 2));
  _chk('round-trip omits empty note', !noNote.toJson().containsKey('note') && Appointment.fromJson(noNote.toJson()).note == '');

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
