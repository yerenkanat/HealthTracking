/// Notification permission is primed by the UI, not requested blindly at launch.
/// These cover the controller wiring the reminders centre drives; the primer
/// sheet itself is covered in permission_primer_test.dart.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';

void main() {
  AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23), locale: AppLocale.en);

  test('unsupported until a service is attached (tests / no-op builds)', () {
    final c = make();
    addTearDown(c.dispose);
    expect(c.notificationsSupported, isFalse);
    expect(c.notificationsAsked, isFalse);
  });

  test('delegates granted/request to the attached service', () async {
    final c = make();
    addTearDown(c.dispose);
    var requested = false;
    c.attachNotificationPermission(
      request: () async {
        requested = true;
        return true;
      },
      granted: () async => false,
    );
    expect(c.notificationsSupported, isTrue);
    expect(await c.notificationsGranted(), isFalse); // service says not yet granted
    expect(await c.requestNotifications(), isTrue); // request fires and reports grant
    expect(requested, isTrue);
  });

  test('marks "asked" so the primer only shows once per run', () {
    final c = make();
    addTearDown(c.dispose);
    c.attachNotificationPermission(request: () async => true, granted: () async => false);
    expect(c.notificationsAsked, isFalse);
    c.markNotificationsAsked();
    expect(c.notificationsAsked, isTrue);
  });

  test('an already-granted service reports true (UI then skips the primer)', () async {
    final c = make();
    addTearDown(c.dispose);
    c.attachNotificationPermission(request: () async => true, granted: () async => true);
    expect(await c.notificationsGranted(), isTrue);
  });
}
