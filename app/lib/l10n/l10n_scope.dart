/// Flutter glue for localization: an InheritedWidget that exposes the active
/// [L10n] to the widget tree. Falls back to English when no scope is present, so
/// widgets (and widget tests without a scope) always have strings.
library;

import 'package:flutter/widgets.dart';
import 'l10n.dart';

class L10nScope extends InheritedWidget {
  final L10n l10n;
  const L10nScope({super.key, required this.l10n, required super.child});

  static L10n of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<L10nScope>();
    return scope?.l10n ?? const L10n(AppLocale.en);
  }

  @override
  bool updateShouldNotify(L10nScope oldWidget) => oldWidget.l10n.locale != l10n.locale;
}

Locale appLocaleToFlutter(AppLocale l) => Locale(l.name);

const supportedFlutterLocales = <Locale>[Locale('ru'), Locale('kk'), Locale('en')];
