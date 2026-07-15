/// FcsApp — root widget. Watches AppController and, whenever an emergency is
/// latched (from the band on-device OR a server-escalated chat), it renders the
/// Emergency Rescue screen OVER everything else. This is the app-wide guarantee
/// that a critical reading always reaches the user.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_controller.dart';
import '../ui/theme.dart';
import '../ui/home_shell.dart';
import '../ui/emergency/emergency_rescue_screen.dart';

class FcsApp extends StatelessWidget {
  final AppController controller;
  const FcsApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umay',
      debugShowCheckedModeBanner: false,
      theme: FcsTheme.light(),
      darkTheme: FcsTheme.dark(),
      home: StreamBuilder<void>(
        stream: controller.changes,
        builder: (context, _) {
          if (controller.route == AppRoute.emergency && controller.emergency != null) {
            final e = controller.emergency!;
            return EmergencyRescueScreen(
              message: e.message,
              callButtons: [
                for (final b in e.callButtons) EmergencyCallButton(b.label, b.tel),
              ],
              onCall: (button) => _dial(button.tel),
              onDismissConfirmed: () async => controller.dismissEmergency(),
            );
          }
          return HomeShell(controller: controller);
        },
      ),
    );
  }

  Future<void> _dial(String tel) async {
    final uri = Uri(scheme: 'tel', path: tel);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
