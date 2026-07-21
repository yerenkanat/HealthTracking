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
import '../data/content_store.dart';
import '../domain/timeline_content.dart';
import '../ui/theme.dart';
import '../ui/home_shell.dart';
import '../ui/onboarding/onboarding_flow.dart';
import '../ui/emergency/emergency_rescue_screen.dart';

/// Flushes any debounced save when the app leaves the foreground.
///
/// Writes are coalesced so a burst of taps does not re-encode the whole config
/// each time, which costs at most 300ms of input if the process dies. Android
/// kills BACKGROUNDED apps, not foreground ones, so writing on the way out
/// closes the window that actually occurs.
class _SaveOnPause extends StatefulWidget {
  final AppController controller;
  final Widget child;
  const _SaveOnPause({required this.controller, required this.child});

  @override
  State<_SaveOnPause> createState() => _SaveOnPauseState();
}

class _SaveOnPauseState extends State<_SaveOnPause> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final leaving = state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
    if (leaving) widget.controller.flushPendingSave();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class FcsApp extends StatelessWidget {
  final AppController controller;

  /// Timeline content in use. Starts from whatever was available locally and
  /// is swapped for the published catalogue once the API answers.
  final ContentStore content;
  const FcsApp({super.key, required this.controller, required this.content});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: controller.changes,
      builder: (context, _) {
        final l = L10n(controller.locale);
        return _SaveOnPause(
          controller: controller,
          child: L10nScope(
          l10n: l,
          child: MaterialApp(
            title: 'Umay',
            debugShowCheckedModeBanner: false,
            theme: FcsTheme.light(),
            themeMode: ThemeMode.light,
            locale: appLocaleToFlutter(controller.locale),
            supportedLocales: supportedFlutterLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _rootFor(l),
          ),
          ),
        );
      },
    );
  }

  Widget _rootFor(L10n l) {
    // First run: gate the whole app behind onboarding.
    if (!controller.onboarded) {
      return OnboardingFlow(
        controller: controller.onboarding,
        onLocaleChange: controller.setLocale,
        onComplete: controller.completeOnboarding,
      );
    }
    if (controller.route == AppRoute.emergency && controller.emergency != null) {
      final e = controller.emergency!;
      // On-device emergencies carry a triage code → localize here. Chat-driven
      // ones already carry a localized message from the server.
      final message = e.code != null ? l.triageMessage(e.code) : e.message;
      return EmergencyRescueScreen(
        message: message,
        // The number that set this off. On a call to 103 or to her doctor, the
        // first question is what the reading was — she should not have to leave
        // this screen to find it.
        details: [
          if (e.readingKind != null && e.readingValue != null)
            l.t('em_reading_${e.readingKind}', {'v': e.readingValue!}),
        ],
        callButtons: [
          for (final b in e.callButtons) EmergencyCallButton(_localizeButton(l, b.label), b.tel),
        ],
        onCall: (button) => _dial(button.tel),
        onDismissConfirmed: () async => controller.dismissEmergency(),
      );
    }
    // Rebuild when a fresher catalogue arrives, so content published in the
    // back-office appears without waiting for a cold start.
    return ValueListenableBuilder<ContentCatalog>(
      valueListenable: content,
      builder: (_, catalog, __) => HomeShell(controller: controller, catalog: catalog),
    );
  }

  /// Map the well-known default button labels to localized strings; leave any
  /// custom server-provided label as-is.
  String _localizeButton(L10n l, String label) => switch (label) {
        EmergencyLabels.ambulance => l.t('em_call_ambulance'),
        EmergencyLabels.doctor => l.t('em_call_doctor'),
        _ => label,
      };

  Future<void> _dial(String tel) async {
    final uri = Uri(scheme: 'tel', path: tel);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
