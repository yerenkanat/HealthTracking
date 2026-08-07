/// The way out of a «not ours» refusal.
///
/// The backend has had `deviceByActivationCode` all along, documented as "the
/// fallback path: units already in the wild whose serial nobody captured", with
/// no route, no controller method and no screen. So a customer holding a
/// genuine watch whose serial was never recorded at intake — which, until every
/// box has been through Приёмка, is most of them — had a refusal and nowhere to
/// go. That is why DEVICE_REGISTRY_ENFORCE is still off: switching it on would
/// have turned away people who paid us.
///
/// The chain is what matters here. Four finished pieces with nothing joining
/// them is this repo's signature defect, and it is what this feature exists to
/// undo — so the test drives the controller, not the widgets in isolation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/device_pairing.dart';
import 'package:fcs_app/domain/family.dart';

void main() {
  /// A controller wired the way main.dart wires it.
  AppController wired({
    required Future<Map<String, dynamic>?> Function(String) claim,
    Future<void> Function(PairedDevice)? upsert,
  }) {
    final c = AppController();
    c.attachDeviceSync(
      upsert: upsert ?? (_) async {},
      delete: (_) async {},
      claim: claim,
    );
    return c;
  }

  test('a good code claims the unit and pairs the serial the SERVER knows', () async {
    // Pairing uses the serial that came back, not whatever the phone scanned —
    // the mismatch between those two is the entire reason she is here.
    final paired = <PairedDevice>[];
    final c = wired(
      claim: (code) async => {'serial': 'AABBCC000001', 'kind': 'band'},
      upsert: (d) async => paired.add(d),
    );
    addTearDown(c.dispose);

    final r = await c.claimDevice('KZ-1234', kind: DeviceKind.band, name: 'Часы');
    expect(r, DeviceClaimResult.ok);
    expect(paired.single.id, 'AABBCC000001');
    expect(c.devices.single.id, 'AABBCC000001');
  });

  test('a tag keeps the child it was being paired for', () async {
    // She was halfway through adding a tracker for a named child when the
    // refusal interrupted her. Losing that is making her start again.
    final c = wired(claim: (_) async => {'serial': 'TAG-1', 'kind': 'tag'});
    addTearDown(c.dispose);
    await c.claimDevice('KZ-1', kind: DeviceKind.tag, childId: 'child-7');
    expect(c.devices.single.childId, 'child-7');
  });

  group('each refusal is its own answer', () {
    test('a code that matches nothing is the one she can fix herself', () async {
      final c = wired(claim: (_) async => null);
      addTearDown(c.dispose);
      expect(await c.claimDevice('NOPE', kind: DeviceKind.band),
          DeviceClaimResult.unknownCode);
      // And nothing was paired on the strength of a miss.
      expect(c.devices, isEmpty);
    });

    test('already claimed', () async {
      final c = wired(claim: (_) async => throw Exception('409 {"error":"already_claimed"}'));
      addTearDown(c.dispose);
      expect(await c.claimDevice('KZ-1', kind: DeviceKind.band),
          DeviceClaimResult.alreadyClaimed);
    });

    test('blocked', () async {
      final c = wired(claim: (_) async => throw Exception('403 {"error":"device_blocked"}'));
      addTearDown(c.dispose);
      expect(await c.claimDevice('KZ-1', kind: DeviceKind.band),
          DeviceClaimResult.blocked);
    });

    test('rate limited', () async {
      final c = wired(claim: (_) async => throw Exception('429 {"error":"too_many_attempts"}'));
      addTearDown(c.dispose);
      expect(await c.claimDevice('KZ-1', kind: DeviceKind.band),
          DeviceClaimResult.tooManyAttempts);
    });

    test('no signal is not "wrong code" — the code was not spent', () async {
      // Telling her the code is wrong when the network failed sends her back to
      // the box to re-read a code that was fine.
      final c = wired(claim: (_) async => throw Exception('SocketException'));
      addTearDown(c.dispose);
      expect(await c.claimDevice('KZ-1', kind: DeviceKind.band),
          DeviceClaimResult.offline);
    });

    test('the five outcomes are five, not a bool', () async {
      // Collapsing them into "it did not work" is what makes a customer give up
      // on a device she legitimately owns.
      expect(DeviceClaimResult.values.length, 6);
    });
  });

  test('a build with no server offers nothing rather than failing oddly', () async {
    final c = AppController();
    addTearDown(c.dispose);
    // attachDeviceSync never called: no claim function at all.
    expect(c.canClaimDevice, isFalse);
    expect(await c.claimDevice('KZ-1', kind: DeviceKind.band),
        DeviceClaimResult.offline);
  });

  test('a wired build says it can offer the way out', () async {
    // What the refusal snackbar reads to decide whether to show the action. A
    // button that opens a sheet that cannot do anything is worse than no button.
    final c = wired(claim: (_) async => null);
    addTearDown(c.dispose);
    expect(c.canClaimDevice, isTrue);
  });
}
