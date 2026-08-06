/// Opening sign-in, from anywhere that needs it.
///
/// Extracted from the Settings screen when the setup checklist grew a "sign
/// in" step: two call sites choosing their own auth provider would be two
/// answers to "is this build talking to a server", and the wrong one mints an
/// account that lives on one handset.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/server_phone_auth.dart';
import '../../domain/phone_auth.dart';
import 'sign_in_screen.dart';

/// The API this build was compiled against. Empty in a dev build with no
/// --dart-define=API_BASE, which is the only case the stub provider is for.
const apiBaseForAuth = String.fromEnvironment('API_BASE');

/// Push the sign-in screen and record the session it returns.
///
/// Real sign-in whenever the app knows a server; the stub only when it does
/// not. The stub mints an account that exists on this phone alone — reinstall
/// and everything recorded is gone — so it must never be reached by a build
/// that could have talked to the real one.
Future<void> openSignIn(BuildContext context, AppController c) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => SignInScreen(
      provider: apiBaseForAuth.isEmpty
          ? const StubPhoneAuthProvider(now: DateTime.now)
          : ServerPhoneAuthProvider(baseUrl: apiBaseForAuth, now: DateTime.now),
      onSignedIn: (session) {
        c.signIn(session);
        Navigator.of(context).pop();
      },
    ),
  ));
}
