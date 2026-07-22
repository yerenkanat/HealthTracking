/// Profile backup: editing the profile pushes it to the backend when a sync
/// hook is attached (push-only; the device stays the source of truth).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';

void main() {
  test('updating the profile pushes it when sync is attached', () async {
    final c = AppController(now: () => DateTime.utc(2026, 7, 22), locale: AppLocale.ru);
    addTearDown(c.dispose);
    final pushed = <UserProfile>[];
    c.attachProfileSync((p) async => pushed.add(p));

    c.updateProfile(const UserProfile(displayName: 'Aigerim', dialCode: '+7', phoneNumber: '7001234567'));
    await Future<void>.delayed(Duration.zero); // let the fire-and-forget run

    expect(pushed, hasLength(1));
    expect(pushed.first.displayName, 'Aigerim');
    expect(pushed.first.e164, '+77001234567');
  });

  test('no push when no sync hook is attached (offline / signed out)', () async {
    final c = AppController(now: () => DateTime.utc(2026, 7, 22), locale: AppLocale.ru);
    addTearDown(c.dispose);
    // Must not throw with no hook wired.
    c.updateProfile(const UserProfile(displayName: 'Madina'));
    await Future<void>.delayed(Duration.zero);
    expect(c.profile.displayName, 'Madina');
  });
}
