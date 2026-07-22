/// The controller's online/offline flag that drives the home-shell offline
/// banner. (The connectivity_plus plugin itself is wired in main.dart and kept
/// out of the widget tree; this covers the state it feeds.)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';

void main() {
  test('starts online, and setOnline flips the offline flag + notifies', () async {
    final c = AppController(now: () => DateTime(2026, 7, 22), locale: AppLocale.ru);
    addTearDown(c.dispose);
    expect(c.isOnline, isTrue);
    expect(c.isOffline, isFalse);

    var changes = 0;
    final sub = c.changes.listen((_) => changes++);
    addTearDown(sub.cancel);

    c.setOnline(false);
    await Future<void>.delayed(Duration.zero);
    expect(c.isOffline, isTrue);
    expect(changes, greaterThan(0));

    // Setting the same value again does not re-notify.
    final before = changes;
    c.setOnline(false);
    await Future<void>.delayed(Duration.zero);
    expect(changes, before);

    c.setOnline(true);
    await Future<void>.delayed(Duration.zero);
    expect(c.isOnline, isTrue);
  });
}
