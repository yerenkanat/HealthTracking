/// What colour a tracker battery is drawn in.
///
/// docs/CLAUDE-app-design.md §"Тревога и цвет": «Красный только SOS.
/// Батарейка, потеря связи, пропущенный скрининг — янтарные.»
///
/// A flat tracker battery used to be drawn in [Palette.danger] — the same red
/// as an SOS — in both places the battery appears. That is the whole
/// alarm-fatigue failure in one colour: a parent who sees red for a battery
/// twice a week learns to read past the colour that means her child pressed
/// the panic button.
///
/// Critical and low are therefore the SAME amber. What separates them is the
/// icon (`battery_alert` against `battery_2_bar`) and the percentage next to
/// it, which say "how bad" without borrowing the one colour that is spoken for.
///
/// Lives in one place because it was two, in two files, and two copies of a
/// colour rule is how one of them stays red after the other is fixed.
library;

import 'package:flutter/material.dart';
import '../../domain/battery.dart';
import '../theme.dart';

Color batteryColor(int pct) => switch (batteryLevel(pct)) {
      // Amber, not red — see the note above.
      BatteryLevel.critical => Palette.amber,
      BatteryLevel.low => Palette.amber,
      BatteryLevel.ok => Palette.textDim,
      BatteryLevel.full => Palette.good,
    };
