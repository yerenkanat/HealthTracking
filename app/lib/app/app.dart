/// FcsApp — root widget. Watches AppController and, whenever an emergency is
/// latched (from the band on-device OR a server-escalated chat), it renders the
/// Emergency Rescue screen OVER everything else. This is the app-wide guarantee
/// that a critical reading always reaches the user.
///
/// Localization: default Russian (per product spec); Kazakh + English supported.
/// The active L10n is provided to the whole tree via L10nScope.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_controller.dart';
import '../l10n/l10n.dart';
import '../l10n/l10n_scope.dart';
import '../ui/theme.dart';
import '../ui/home_shell.dart';
import '../ui/emergency/emergency_rescue_screen.dart';

class FcsApp extends StatelessWidget {
  final AppController controller;
  const FcsApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: controller.changes,
      builder: (context, _) {
        final l = L10n(controller.locale);
        return L10nScope(
          l10n: l,
          child: MaterialApp(
            title: 'Umay',
            debugShowCheckedModeBanner: false,
            theme: FcsTheme.light(),
            darkTheme: FcsTheme.dark(),
            locale: appLocaleToFlutter(controller.locale),
            supportedLocales: supportedFlutterLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _rootFor(l),
          ),
        );
      },
    );
  }

  Widget _rootFor(L10n l) {
    if (controller.route == AppRoute.emergency && controller.emergency != null) {
      final e = controller.emergency!;
      // On-device emergencies carry a triage code → localize here. Chat-driven
      // ones already carry a localized message from the server.
      final message = e.code != null ? l.triageMessage(e.code) : e.message;
      return EmergencyRescueScreen(
        message: message,
        callButtons: [
          for (final b in e.callButtons) EmergencyCallButton(_localizeButton(l, b.label), b.tel),
        ],
        onCall: (button) => _dial(button.tel),
        onDismissConfirmed: () async => controller.dismissEmergency(),
      );
    }
    return HomeShell(controller: controller);
  }

  /// Map the well-known default button labels to localized strings; leave any
  /// custom server-provided label as-is.
  String _localizeButton(L10n l, String label) => switch (label) {
        'Call ambulance' => l.t('em_call_ambulance'),
        'Call your doctor' => l.t('em_call_doctor'),
        _ => label,
      };

  Future<void> _dial(String tel) async {
    final uri = Uri(scheme: 'tel', path: tel);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
