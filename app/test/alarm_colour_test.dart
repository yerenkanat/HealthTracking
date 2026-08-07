/// «Красный только SOS. Батарейка, потеря связи, пропущенный скрининг —
/// янтарные.»
///
/// docs/CLAUDE-app-design.md §"Тревога и цвет", and the merge checklist line
/// «Красный нигде, кроме SOS».
///
/// This is an alarm-fatigue rule, not a taste one. A flat tracker battery was
/// drawn in [Palette.danger] — the same red as an SOS — in THREE places, and a
/// parent who sees that red twice a week for a battery learns to read past the
/// one colour that means her child pressed the panic button. By the time it
/// matters the colour has stopped meaning anything.
///
/// Critical and low share amber on purpose. What separates them is the icon
/// and the percentage beside it, which say "how bad" without borrowing the
/// colour that is spoken for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/battery.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/widgets/battery_colors.dart';

void main() {
  group('a tracker battery is never SOS red', () {
    test('flat is amber, not danger', () {
      // 5% is [BatteryLevel.critical] — the case that used to be red.
      expect(batteryLevel(5), BatteryLevel.critical);
      expect(batteryColor(5), Palette.amber);
      expect(batteryColor(5), isNot(Palette.danger));
    });

    test('nothing on the scale is danger', () {
      for (var pct = -10; pct <= 110; pct++) {
        expect(batteryColor(pct), isNot(Palette.danger),
            reason: '$pct% is drawn in the SOS colour');
      }
    });

    test('critical and low are the same colour, deliberately', () {
      // Two ambers a shade apart would read as a gradient nobody can decode.
      // The icon carries the difference.
      expect(batteryColor(5), batteryColor(20));
      expect(batteryLevel(5), BatteryLevel.critical);
      expect(batteryLevel(20), BatteryLevel.low);
    });

    test('healthy levels are not amber either — that would cry wolf too', () {
      expect(batteryColor(60), Palette.textDim);
      expect(batteryColor(95), Palette.good);
    });

    test('out-of-range readings do not fall through to a null colour', () {
      // A device reporting 120% or -1 is a device with a bug, not a reason for
      // an uncoloured chip on a parent's screen.
      expect(batteryColor(-1), batteryColor(0));
      expect(batteryColor(120), batteryColor(100));
    });
  });

  group('the colours are actually distinct', () {
    test('amber, danger and good are three different colours', () {
      // The rule above is worth nothing if `Palette.amber` and `Palette.danger`
      // happen to be the same value — every assertion would pass vacuously.
      final all = <Color>{Palette.amber, Palette.danger, Palette.good, Palette.textDim};
      expect(all, hasLength(4));
    });
  });
}
