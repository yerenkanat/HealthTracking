/// Verifies that the OS notification id blocks stay disjoint.
///
/// The OS has one id namespace for everything. Two blocks that overlap show up
/// as a reminder that silently never arrives, or a safety alert that quietly
/// replaces another — never as an error. That is exactly the kind of thing a
/// hand-maintained list of magic numbers in three files stops guaranteeing the
/// moment someone adds a fourth.
library;

import '../lib/domain/notification_ids.dart';

int _passed = 0, _failed = 0;

void _chk(String name, bool ok) {
  if (ok) {
    _passed++;
  } else {
    _failed++;
    print('  FAIL: $name');
  }
}

void main() {
  // ---- blocks are disjoint ----
  for (var i = 0; i < NotifyIds.blocks.length; i++) {
    for (var j = i + 1; j < NotifyIds.blocks.length; j++) {
      final a = NotifyIds.blocks[i], b = NotifyIds.blocks[j];
      _chk('${a.name} does not overlap ${b.name}', a.end < b.start || b.end < a.start);
    }
  }
  _chk('every block is non-empty', NotifyIds.blocks.every((b) => b.end >= b.start));
  _chk('no block reaches into negative ids', NotifyIds.blocks.every((b) => b.start > 0));

  // ---- fixed ids sit in their declared block ----
  final cycle = NotifyIds.blocks.firstWhere((b) => b.name == 'cycle');
  final daily = NotifyIds.blocks.firstWhere((b) => b.name == 'daily');
  _chk('period id is in the cycle block', cycle.contains(NotifyIds.period));
  _chk('fertile id is in the cycle block', cycle.contains(NotifyIds.fertile));
  _chk('period and fertile differ', NotifyIds.period != NotifyIds.fertile);
  _chk('water id is in the daily block', daily.contains(NotifyIds.water));
  _chk('medication id is in the daily block', daily.contains(NotifyIds.medication));
  _chk('water and medication differ', NotifyIds.water != NotifyIds.medication);

  // ---- generated ids stay inside their block ----
  final appts = NotifyIds.blocks.firstWhere((b) => b.name == 'appointments');
  _chk('appointment ids stay in the appointment block', () {
    for (var i = 0; i < 5000; i++) {
      if (!appts.contains(NotifyIds.forAppointment('appt-$i-${i * 7919}'))) return false;
    }
    return true;
  }());
  _chk('an empty appointment id is still in block',
      appts.contains(NotifyIds.forAppointment('')));
  _chk('a unicode appointment id is still in block',
      appts.contains(NotifyIds.forAppointment('приём-🤰-2026')));
  _chk('appointment ids are stable across calls',
      NotifyIds.forAppointment('appt-42') == NotifyIds.forAppointment('appt-42'));
  _chk('different appointments generally differ',
      NotifyIds.forAppointment('appt-1') != NotifyIds.forAppointment('appt-2'));

  final alerts = NotifyIds.blocks.firstWhere((b) => b.name == 'alerts');
  // The alert sequence is seeded from the clock so a restart does not reuse the
  // previous run's ids, which means it starts at a large number — it must wrap
  // inside its own block rather than counting up into the cycle block and
  // cancelling a pending reminder.
  _chk('alert ids stay in the alert block from a clock seed', () {
    var seq = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (var i = 0; i < 5000; i++) {
      if (!alerts.contains(NotifyIds.forAlert(seq++))) return false;
    }
    return true;
  }());
  _chk('alert id 0 is in block', alerts.contains(NotifyIds.forAlert(0)));
  _chk('a huge sequence still lands in block',
      alerts.contains(NotifyIds.forAlert(0x7fffffffffffff)));
  _chk('consecutive alerts differ',
      NotifyIds.forAlert(7) != NotifyIds.forAlert(8));

  // ---- the cross-block guarantee, stated directly ----
  _chk('no generated alert id can ever equal a fixed reminder id', () {
    for (final fixed in [NotifyIds.period, NotifyIds.fertile, NotifyIds.water, NotifyIds.medication]) {
      if (alerts.contains(fixed)) return false;
    }
    return true;
  }());

  print('$_passed passed, $_failed failed');
  if (_failed > 0) throw Exception('notification id verification failed');
}
