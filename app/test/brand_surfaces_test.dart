/// The brand surfaces that live OUTSIDE the Flutter tree.
///
/// The splash window, the launch mark and the notification shade are drawn by
/// Android from `res/`, not by any widget — so no golden, no accessibility
/// check and no render test covers them. All three were still the previous
/// palette after the whole app had moved, and the only way to notice was to
/// launch the app on a device and look at the first frame.
///
/// These assert on the resource files themselves, which is the cheapest thing
/// that would have caught it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ui/design_system.dart';

String _hex(int argb) => '#${argb.toRadixString(16).toUpperCase().padLeft(8, '0')}';

void main() {
  final res = Directory('android/app/src/main/res');

  group('the Android launch surfaces carry the current brand', () {
    test('the splash window background is Ds.cream', () {
      final xml = File('${res.path}/values/colors.xml').readAsStringSync();
      // The first frame of the app. It was #FBF5EF — the old cream — so the app
      // opened one colour and then became another.
      expect(xml, contains(_hex(Ds.cream.toARGB32())));
    });

    test('the splash mark is Ds.coral, not the old terracotta', () {
      final xml = File('${res.path}/drawable/brand_mark.xml').readAsStringSync();
      // The fill attribute specifically — the file's comment names the old
      // colour to say what it replaced, and a whole-file match trips on that.
      final fills = RegExp(r'android:fillColor="(#[0-9A-Fa-f]+)"')
          .allMatches(xml)
          .map((m) => m.group(1)!.toUpperCase())
          .toList();
      expect(fills, isNotEmpty);
      expect(fills, everyElement(equals('#FF3D71')));
    });

    test('the notification accent is the CTA coral', () {
      final xml = File('${res.path}/values/colors.xml').readAsStringSync();
      expect(xml, contains(_hex(Ds.coralCta.toARGB32())));
    });
  });

  group('the notification icon can actually be rendered', () {
    test('a white silhouette exists for the status bar', () {
      final f = File('${res.path}/drawable/ic_notification.xml');
      expect(f.existsSync(), isTrue);
      // Android ≥5 masks the small icon and tints it, so anything but white
      // comes out as a featureless blob.
      expect(f.readAsStringSync(), contains('#FFFFFFFF'));
    });

    test('the service uses it rather than the full-colour launcher icon', () {
      final dart = File('lib/data/notification_service.dart').readAsStringSync();
      expect(dart, contains("AndroidInitializationSettings('@drawable/ic_notification')"));
      expect(dart, isNot(contains("AndroidInitializationSettings('@mipmap/ic_launcher')")));
    });

    test('every notification carries the brand colour', () {
      final dart = File('lib/data/notification_service.dart').readAsStringSync();
      final details = 'AndroidNotificationDetails('.allMatches(dart).length;
      final coloured = 'color: _brand,'.allMatches(dart).length;
      expect(details, greaterThan(0));
      expect(coloured, details,
          reason: 'a notification without it shows the platform default, and '
              'nothing in the shade says Ana-Bala');
    });
  });
}
