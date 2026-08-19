/// Is the app in front of her, right now?
///
/// One fact, published once. `AppLifecycleState` is observed in exactly ONE
/// place in this app — `_LifecycleHooks` in `app/app.dart` — and that observer
/// writes here. Everything that needs to know listens; nothing else registers a
/// second `WidgetsBindingObserver`, because two observers of the same signal
/// drift apart the first time one of them disagrees about what `inactive`
/// means, and the disagreement is invisible until a device behaves oddly.
///
/// "Foreground" here means the same thing it already meant to that observer:
/// NOT paused, hidden or detached. `inactive` counts as foreground — on iOS it
/// fires when the notification shade is pulled down or a call comes in, while
/// the screen she is looking at is still on screen. Treating that as background
/// would drop the BLE scan to low power dozens of times a day for a second at a
/// time, each drop costing a stop/start of the radio.
///
/// Starts `true`: the process exists because she opened the app.
library;

import 'package:flutter/foundation.dart';

class AppForeground extends ValueNotifier<bool> {
  AppForeground({bool foreground = true}) : super(foreground);

  /// The instance the running app uses. Tests build their own and inject it
  /// (see `BleManagerConfig.foreground`) rather than mutating this one, so a
  /// test that forgets to restore it cannot leak into the next one.
  static final AppForeground instance = AppForeground();
}
