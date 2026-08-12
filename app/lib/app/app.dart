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
import '../ble/band_scan.dart';
import '../l10n/l10n.dart';
import '../l10n/l10n_scope.dart';
import '../data/content_store.dart';
import '../domain/notification_route.dart';
import '../domain/timeline_content.dart';
import '../ui/theme.dart';
import '../ui/home_shell.dart';
import '../ui/onboarding/onboarding_flow.dart';
import '../ui/settings/legal_consent_screen.dart';
import '../ui/emergency/emergency_rescue_screen.dart';
import '../ui/tracking/sos_alert_screen.dart';
import '../ui/tracking/tracking_map.dart';
import '../ui/force_update_screen.dart';

/// The two things the app owes the operating system's lifecycle.
///
/// **Leaving:** flush any debounced save. Writes are coalesced so a burst of
/// taps does not re-encode the whole config each time, which costs at most
/// 300ms of input if the process dies. Android kills BACKGROUNDED apps, not
/// foreground ones, so writing on the way out closes the window that actually
/// occurs.
///
/// **Coming back:** re-read her рассылки. A phone spends days backgrounded, and
/// a broadcast published in that time was fetched by nobody — the startup pull
/// runs once per cold launch, which on Android can be weeks apart. Resuming is
/// the moment she is looking at the app again, so it is the moment the bell
/// badge has to be true.
class _LifecycleHooks extends StatefulWidget {
  final AppController controller;
  final Widget child;
  const _LifecycleHooks({required this.controller, required this.child});

  @override
  State<_LifecycleHooks> createState() => _LifecycleHooksState();
}

class _LifecycleHooksState extends State<_LifecycleHooks> with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshAnnouncements();
    }
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
        return _LifecycleHooks(
          controller: controller,
          child: L10nScope(
          l10n: l,
          child: MaterialApp(
            title: 'Ana-Bala',
            debugShowCheckedModeBanner: false,
            // The locale is a real theme input: Unbounded carries no Kazakh
            // glyphs, so the display family switches to Rubik on kk. Passing it
            // here means the swap happens the moment the language changes.
            theme: FcsTheme.light(controller.locale),
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
    // Before anything else: a build the server has retired is blocked outright.
    // It may be talking to an API it no longer matches or missing a safety fix,
    // so it must not run — not even onboarding or the emergency screen, since a
    // stale client cannot be trusted to render those correctly either.
    if (controller.mustUpdate) {
      return const ForceUpdateScreen();
    }
    // First run: gate the whole app behind onboarding.
    if (!controller.onboarded) {
      return OnboardingFlow(
        controller: controller.onboarding,
        onLocaleChange: controller.setLocale,
        onComplete: controller.completeOnboarding,
        // The pairing step's scan. Without this the step asks her to choose her
        // watch from a list that is structurally empty — `_PairBandPage` falls
        // back to its skip line when `scanBands` is null, and nothing has ever
        // passed one. The id she picks is persisted as her paired band and is
        // what the watch link reconnects to and stamps on every reading.
        // TODO(design): the page has no copy for "scanned, found nothing" — it
        // shows the scanning line for ever. Wording is design's call.
        scanBands: scanForBands,
      );
    }
    // Returning user, but the privacy policy / terms changed since they last
    // accepted: re-consent before letting them back in.
    if (controller.needsLegalConsent) {
      return LegalConsentScreen(onAccept: controller.acceptLegal);
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
    // Screen 21. Raised over everything for the same reason the emergency
    // screen is: a child has pressed the button, and whatever she had open is
    // no longer the thing on the screen. Dismissing it drops back to the shell
    // with the alert still on the safety feed.
    if (controller.route == AppRoute.sos && controller.sos != null) {
      final s = controller.sos!;
      return SosAlertScreen(
        childName: s.childName,
        at: s.at,
        now: DateTime.now(),
        zoneName: s.zoneName,
        coords: s.coords,
        coordsAt: s.coordsAt,
        contactName: s.contactName,
        contactPhone: s.contactPhone,
        onCall: _dial,
        // «Открыть карту» hands over to the live tracking screen — the takeover
        // closes, the Child tab opens, and the alarm stays in the feed.
        onOpenMap: () {
          controller.dismissSos();
          controller.requestDestination(NotifyDestination.childMap);
        },
        // The real map when this build has a key for one; the position as text
        // when it does not, exactly as the tracking tab behaves.
        mapBuilder: buildTrackingMap,
        onDismissConfirmed: () async => controller.dismissSos(),
      );
    }
    // Rebuild when a fresher catalogue arrives, so content published in the
    // back-office appears without waiting for a cold start.
    return ValueListenableBuilder<ContentCatalog>(
      valueListenable: content,
      builder: (_, catalog, __) => HomeShell(
        controller: controller,
        catalog: catalog,
        // The notifier itself as well as its value: a route PUSHED over the
        // shell — the guides library — sits outside this builder and would
        // otherwise freeze on whatever was published at the moment it opened.
        catalogSource: content,
      ),
    );
  }

  /// Map the well-known default button labels to localized strings; leave any
  /// custom server-provided label as-is.
  String _localizeButton(L10n l, String label) => switch (label) {
        EmergencyLabels.ambulance => l.t('em_call_ambulance'),
        EmergencyLabels.doctor => l.t('em_call_doctor'),
        _ => label,
      };

  /// Place the call. Returns false if the phone could not be opened.
  ///
  /// This used to be `if (await canLaunchUrl(uri)) await launchUrl(uri);` —
  /// so when the check said no, NOTHING happened. She taps "Call ambulance"
  /// during a hypertensive emergency, the screen does not move, and there is
  /// no error, no explanation, and nothing to try instead. She taps it again.
  ///
  /// canLaunchUrl says no for reasons that have nothing to do with whether the
  /// call would work: a device with no dialler (any iPad), an iOS scheme not
  /// declared in LSApplicationQueriesSchemes, a locked-down work profile. So
  /// the launch is now attempted regardless and the RESULT is reported, which
  /// lets the screen fall back to showing her the number to dial by hand.
  Future<bool> _dial(String tel) async {
    try {
      return await launchUrl(Uri(scheme: 'tel', path: tel));
    } catch (_) {
      return false;
    }
  }
}
