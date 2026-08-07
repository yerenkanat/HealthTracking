/// What happens when the server refuses a device.
///
/// The same watches and tags are sold on other marketplaces, so pairing can now
/// come back 403. Adding a device was fire-and-forget, which was fine while the
/// server accepted everything — a refusal nobody surfaces leaves her holding a
/// watch that sits in her list reporting nothing, with no idea why.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/device_pairing.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';

const _tag = PairedDevice(id: 'AA:BB:CC', name: 'Tag', kind: DeviceKind.tag);

AppController _controller(Future<void> Function(PairedDevice) push) {
  final c = AppController(now: () => DateTime.utc(2026, 8, 7), locale: AppLocale.ru);
  c.attachDeviceSync(upsert: push, delete: (_) async {});
  return c;
}

void main() {
  test('a device that is not ours is taken back out of her list', () async {
    // Leaving it would show her a device that never reports anything and never
    // explains itself.
    final c = _controller((_) async =>
        throw ApiException(403, '{"error":"device_not_ours"}'));
    addTearDown(c.dispose);

    final outcome = await c.addDevice(_tag);
    expect(outcome, DevicePairOutcome.notOurs);
    expect(c.devices, isEmpty);
  });

  test('a blocked device is reported as blocked, not as unknown', () async {
    // She needs different words: "this was reported stolen" is not "this did
    // not come from us".
    final c = _controller((_) async =>
        throw ApiException(403, '{"error":"device_blocked"}'));
    addTearDown(c.dispose);

    expect(await c.addDevice(_tag), DevicePairOutcome.blocked);
    expect(c.devices, isEmpty);
  });

  test('offline KEEPS the device — it is re-pushed at the next launch', () async {
    // Removing it here would delete a device she really owns because her train
    // went into a tunnel.
    final c = _controller((_) async => throw Exception('no network'));
    addTearDown(c.dispose);

    expect(await c.addDevice(_tag), DevicePairOutcome.offline);
    expect(c.devices.single.id, 'AA:BB:CC');
  });

  test('a server that is merely unhappy is treated as offline', () async {
    // A 500 is not a judgement about the device.
    final c = _controller((_) async => throw ApiException(500, 'boom'));
    addTearDown(c.dispose);

    expect(await c.addDevice(_tag), DevicePairOutcome.offline);
    expect(c.devices, hasLength(1));
  });

  test('an accepted device stays, and says so', () async {
    final c = _controller((_) async {});
    addTearDown(c.dispose);

    expect(await c.addDevice(_tag), DevicePairOutcome.ok);
    expect(c.devices, hasLength(1));
  });

  test('a build with no server pairs locally rather than hanging', () async {
    final c = AppController(now: () => DateTime.utc(2026, 8, 7), locale: AppLocale.ru);
    addTearDown(c.dispose);
    expect(await c.addDevice(_tag), DevicePairOutcome.ok);
    expect(c.devices, hasLength(1));
  });

  test('both refusals tell her what to do next', () {
    // A bare refusal costs the customer AND the support conversation; somebody
    // holding a tag from another marketplace still wants the service.
    for (final key in ['dev_not_ours', 'dev_blocked']) {
      for (final locale in AppLocale.values) {
        expect(L10n(locale).t(key).toLowerCase(), contains('whatsapp'),
            reason: '$key/$locale does not say how to reach us');
      }
    }
  });
}
