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

  // ---- the guard's own premise ----
  // If the file could not be read, or were empty, every check above would pass
  // vacuously.
  _chk('main.dart was actually read', main_.length > 2000);
  _chk('it is the file we think it is', main_.contains('Future<void> main()'));

  print('$_passed passed, $_failed failed');
  if (_failed > 0) throw Exception('wiring verification failed');
}
