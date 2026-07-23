/// Is the runtime wiring in main.dart actually connected?
///
/// The recurring failure in this codebase is not broken code — it is finished
/// code attached to nothing, which presents as "waiting" or "fine" rather than
/// as an error. ApiClient.lastLocation had no caller, so the tracking map said
/// "waiting for location" for ever. The reminder cancel path was never invoked
/// on erase. Nothing was testing any of that, because each part worked.
///
/// main() cannot be unit-tested — it calls runApp — so this reads it as text
/// and asserts the connections exist. Crude, and it still catches the thing
/// unit tests structurally cannot.
library;

import 'dart:io';

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
  final main_ = File.fromUri(Platform.script.resolve('../lib/main.dart')).readAsStringSync();

  // ---- error handling ----
  _chk('main installs the error handlers', main_.contains('_installErrorHandling('));
  _chk('the handlers write to the controller\'s log, not a private one',
      main_.contains('_installErrorHandling(controller.errorLog)'));
  _chk('FlutterError.onError is assigned', main_.contains('FlutterError.onError ='));
  _chk('async errors are caught', main_.contains('PlatformDispatcher.instance.onError ='));
  _chk('the grey box is replaced', main_.contains('ErrorWidget.builder ='));

  // Handlers installed after runApp miss every error thrown while the first
  // frame is built — which is exactly when a bad restore or a corrupt config
  // shows up.
  final installAt = main_.indexOf('_installErrorHandling(controller');
  final runAppAt = main_.indexOf('runApp(');
  _chk('handlers are installed BEFORE runApp',
      installAt > 0 && runAppAt > 0 && installAt < runAppAt);

  // ---- things that previously existed with no caller ----
  _chk('the child location poll is started', main_.contains('_pollChildLocation('));
  _chk('reminder commands are consumed', main_.contains('reminderCommands.listen'));
  _chk('water reminders are consumed', main_.contains('waterReminderCommands.listen'));
  _chk('medication reminders are consumed', main_.contains('medReminderCommands.listen'));
  _chk('alerts reach the notification service', main_.contains('newAlerts.listen'));
  _chk('reminders are reconciled on boot', main_.contains('rescheduleReminders()'));

  // ---- wearable → controller ----
  // The watch's snapshots must reach the controller, or the whole activity
  // panel goes dark and — since onWearableMetrics is what folds the band's
  // nightly sleep into the history — the sleep card silently shows only
  // hand-logged nights. This edge being deleted presents as "no watch data",
  // indistinguishable from an unpaired watch.
  _chk('watch snapshots reach the controller',
      main_.contains('watch.onSnapshot.listen(controller.onWearableMetrics)'));

  // ---- backend sync hooks ----
  // Each attach*Sync is the edge that mirrors a data type to the server (and so
  // to the clinician's view). BP calibration in particular had a `// TODO` here
  // for a whole release, so its offsets never left the phone. If any of these
  // is dropped, that data type silently stops syncing while the app looks fine.
  for (final hook in [
    'attachSleepSync(',
    'attachMedicationSync(',
    'attachGeofenceSync(',
    'attachNewbornSync(',
    'attachEmergencySync(',
    'attachSessionSync(',
    'attachBpCalibrationSync(',
  ]) {
    _chk('sync hook wired: $hook', main_.contains(hook));
  }

  // ---- new-device restore ----
  // A reinstall must not be an empty app. The restore runs each pull under
  // _restore() inside a Future.wait; if that block is removed, the app still
  // runs, still syncs going forward, and silently never brings her history back.
  _chk('the new-device restore runs', main_.contains('_restore(') && main_.contains('Future.wait('));
  _chk('BP calibration is restored on a new device', main_.contains('api.getBpCalibration()'));
  // Server-detected safety alerts (tracker-tag crossings the phone never saw)
  // must be pulled into the feed, or they exist only in the back-office.
  _chk('server safety alerts are pulled into the app',
      main_.contains('api.getAlerts()') && main_.contains('mergeRemoteAlerts('));

  // ---- the guard's own premise ----
  // If the file could not be read, or were empty, every check above would pass
  // vacuously.
  _chk('main.dart was actually read', main_.length > 2000);
  _chk('it is the file we think it is', main_.contains('Future<void> main()'));

  print('$_passed passed, $_failed failed');
  if (_failed > 0) throw Exception('wiring verification failed');
}
