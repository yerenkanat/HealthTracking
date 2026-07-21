/// Flutter glue for localization: an InheritedWidget that exposes the active
/// [L10n] to the widget tree. Falls back to English when no scope is present, so
/// widgets (and widget tests without a scope) always have strings.
library;

import 'package:flutter/widgets.dart';
import 'l10n.dart';

class L10nScope extends InheritedWidget {
  final L10n l10n;
  const L10nScope({super.key, required this.l10n, required super.child});

  /// The scope's L10n, or English when there is none above [context].
  ///
  /// The English fallback is not the app's default locale (that is Russian),
  /// and it looked like a bug — but it is only reachable when a widget is built
  /// outside the app shell, which FcsApp always wraps in an L10nScope. In
  /// practice that means tests, where a stable, readable default is the point.
  /// Changing it to Russian broke 61 of them and fixed nothing a user could
  /// ever see, so it stays.
  static L10n of(BuildContext context) => maybeOf(context) ?? const L10n(AppLocale.en);

  /// The scope's L10n, or null when there is none above [context].
  ///
  /// Returns null rather than a default so a caller that is ITSELF handling a
  /// failure — the error fallback — can choose its own, instead of silently
  /// getting whichever language [of] happens to default to.
  static L10n? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<L10nScope>();
    return scope?.l10n;
  }

  @override
  bool updateShouldNotify(L10nScope oldWidget) => oldWidget.l10n.locale != l10n.locale;
}

Locale appLocaleToFlutter(AppLocale l) => Locale(l.name);

const supportedFlutterLocales = <Locale>[Locale('ru'), Locale('kk'), Locale('en')];
