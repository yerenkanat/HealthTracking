/// Pure-Dart verification of the emergency confirmation gate.
/// `dart run tool/verify_emergency_confirmation.dart`
///
/// This decides when a pregnant woman's screen is taken over with "seek
/// emergency care now". Both directions are dangerous: escalating on every
/// noisy estimate causes the alarm fatigue that makes the real one ignorable,
/// and failing to escalate a persisting condition is worse still. Every
/// assertion below pins one or the other.
library;

import 'dart:io';
import '../lib/domain/emergency_confirmation.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

final t0 = DateTime.parse('2026-07-20T09:00:00Z');
DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

EscalationDecision sensor(EmergencyConfirmation g, String code, DateTime when) =>
    g.consider(code: code, isEmergency: true, source: ReadingSource.sensor, at: when);

void main() {
  // ---- A single sensor estimate never takes over the screen ----
  {
    final g = EmergencyConfirmation();
    final first = sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('the first crossing asks for another reading', first.shouldAskToRepeat);
    _chk('the first crossing does not escalate', !first.shouldEscalate);
    _chk('the decision names the code it is about', first.code == 'PREECLAMPSIA_BP');
  }

  // ---- A condition that persists does escalate ----
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('a crossing two minutes later escalates',
        sensor(g, 'PREECLAMPSIA_BP', at(120)).shouldEscalate);
  }

  // ---- One artifact cannot confirm itself ----
  // The band emits frames seconds apart. Without a spacing floor the gate would
  // be decorative: a single burst of movement would escalate immediately.
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    var escalatedEarly = false;
    for (var s = 5; s < 120; s += 5) {
      if (sensor(g, 'PREECLAMPSIA_BP', at(s)).shouldEscalate) escalatedEarly = true;
    }
    _chk('a burst of frames inside the spacing window never escalates', !escalatedEarly);
    _chk('and it still escalates once the spacing is met',
        sensor(g, 'PREECLAMPSIA_BP', at(120)).shouldEscalate);
  }

  // Repeat frames must not re-prompt on every reading either.
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    var prompts = 0;
    for (var s = 5; s < 120; s += 5) {
      if (sensor(g, 'PREECLAMPSIA_BP', at(s)).shouldAskToRepeat) prompts++;
    }
    _chk('she is asked to measure again once, not on every frame', prompts == 0);
  }

  // Spacing is measured from the FIRST crossing, not pushed forward by each
  // frame that follows — otherwise a steady stream would never confirm.
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    for (var s = 10; s <= 110; s += 10) {
      sensor(g, 'PREECLAMPSIA_BP', at(s));
    }
    _chk('a steady stream of crossings still confirms on time',
        sensor(g, 'PREECLAMPSIA_BP', at(120)).shouldEscalate);
  }

  // ---- A one-off expires quietly ----
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    final muchLater = sensor(g, 'PREECLAMPSIA_BP', at(60 * 60 * 2));
    _chk('an unrelated crossing hours later starts over, it does not escalate',
        muchLater.shouldAskToRepeat);
  }

  // ---- After escalating, the next episode counts from scratch ----
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('escalates once', sensor(g, 'PREECLAMPSIA_BP', at(120)).shouldEscalate);
    _chk('the next crossing does not escalate instantly off the last episode',
        sensor(g, 'PREECLAMPSIA_BP', at(130)).shouldAskToRepeat);
  }

  // ---- A worsening condition is the same condition ----
  // Crossing the ordinary threshold and then the severe one is exactly the case
  // that should escalate soonest. Keying on the exact code would restart the
  // count instead — the opposite of what it should do.
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('an ordinary crossing then a severe one escalates',
        sensor(g, 'PREECLAMPSIA_BP_SEVERE', at(120)).shouldEscalate);
  }
  _chk('both blood-pressure codes are one condition',
      emergencyFamily('PREECLAMPSIA_BP') == emergencyFamily('PREECLAMPSIA_BP_SEVERE'));
  _chk('both fever codes are one condition',
      emergencyFamily('HIGH_FEVER') == emergencyFamily('LOW_FEVER'));
  _chk('blood pressure and fever are not the same condition',
      emergencyFamily('PREECLAMPSIA_BP') != emergencyFamily('HIGH_FEVER'));
  _chk('an unrecognised code stands alone rather than joining a family',
      emergencyFamily('SOMETHING_NEW') == 'SOMETHING_NEW');

  // ---- Separate conditions are tracked separately ----
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('a fever crossing does not confirm a blood-pressure one',
        sensor(g, 'HIGH_FEVER', at(120)).shouldAskToRepeat);
    _chk('and the blood-pressure one still confirms on its own',
        sensor(g, 'PREECLAMPSIA_BP', at(130)).shouldEscalate);
  }

  // ---- A hand-entered reading is not an estimate ----
  {
    final g = EmergencyConfirmation();
    final typed = g.consider(
      code: 'PREECLAMPSIA_BP',
      isEmergency: true,
      source: ReadingSource.manual,
      at: at(0),
    );
    _chk('a reading she took by hand escalates immediately', typed.shouldEscalate);
    _chk('it does not ask her to repeat what she just measured',
        !typed.shouldAskToRepeat);
  }

  // ---- Nothing below emergency severity is touched ----
  {
    final g = EmergencyConfirmation();
    final calm = g.consider(
      code: null, isEmergency: false, source: ReadingSource.sensor, at: at(0));
    _chk('a normal reading produces no action', calm.action == EscalationAction.none);
    _chk('and leaves nothing pending behind it', !g.isPending('bp'));
  }

  // ---- A normal reading must not cancel a pending rise ----
  // Sensor noise cuts both ways. Letting one low estimate clear a real rise
  // would put the gate's error in the dangerous direction.
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    g.consider(code: null, isEmergency: false, source: ReadingSource.sensor, at: at(60));
    _chk('a normal reading in between does not cancel the pending crossing',
        sensor(g, 'PREECLAMPSIA_BP', at(120)).shouldEscalate);
  }

  // ---- Pending state is inspectable and clearable ----
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('a pending crossing is visible to the UI', g.isPending('bp'));
    g.clear();
    _chk('clearing forgets it', !g.isPending('bp'));
    _chk('and the next crossing starts over',
        sensor(g, 'PREECLAMPSIA_BP', at(10)).shouldAskToRepeat);
  }

  // ---- The window boundary ----
  {
    final g = EmergencyConfirmation(
      window: const Duration(minutes: 30), minSpacing: const Duration(minutes: 2));
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('inside the window it still confirms',
        sensor(g, 'PREECLAMPSIA_BP', at(30 * 60)).shouldEscalate);
  }
  {
    final g = EmergencyConfirmation(
      window: const Duration(minutes: 30), minSpacing: const Duration(minutes: 2));
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('one second past the window it starts over',
        sensor(g, 'PREECLAMPSIA_BP', at(30 * 60 + 1)).shouldAskToRepeat);
  }
  // Exactly the spacing counts as met — a boundary this code should not be shy
  // about, since the cost of waiting is delaying a real emergency.
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('exactly the minimum spacing confirms',
        sensor(g, 'PREECLAMPSIA_BP', at(120)).shouldEscalate);
  }
  {
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('one second short of it does not',
        !sensor(g, 'PREECLAMPSIA_BP', at(119)).shouldEscalate);
  }

  // ---- What the "take another reading" prompt reads from ----
  //
  // One source of truth. The controller used to keep its own copy, set when a
  // crossing was first seen and cleared only by an escalation or an account
  // reset — while expiry lived here. A lone artifact therefore left the prompt
  // on a pregnant woman's dashboard permanently, with nothing wrong with her.
  {
    final g = EmergencyConfirmation();
    _chk('nothing pending to begin with', g.pendingFamilyAt(at(0)) == null);

    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('a crossing is pending', g.pendingFamilyAt(at(1)) == 'bp');

    // Expiry is a function of time alone: the crossing lapses whether or not
    // another reading ever arrives. Asking at a later instant is enough.
    _chk('inside the window it is still pending',
        g.pendingFamilyAt(at(29 * 60)) == 'bp');
    _chk('past the window it is gone', g.pendingFamilyAt(at(31 * 60)) == null);
  }
  {
    // Escalating resolves it — the prompt must not survive the emergency it
    // was asking about.
    final g = EmergencyConfirmation();
    sensor(g, 'PREECLAMPSIA_BP', at(0));
    _chk('escalation clears the prompt',
        sensor(g, 'PREECLAMPSIA_BP', at(120)).shouldEscalate &&
            g.pendingFamilyAt(at(121)) == null);
  }
  {
    // Two conditions at once: report the older, which is nearest to resolving
    // either way.
    final g = EmergencyConfirmation();
    sensor(g, 'HYPOXIA', at(0));
    sensor(g, 'PREECLAMPSIA_BP', at(30));
    _chk('the oldest pending measurement is the one reported',
        g.pendingFamilyAt(at(60)) == 'spo2');
    _chk('and when it expires the other takes over',
        g.pendingFamilyAt(at(30 * 60 + 20)) == 'bp');
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
