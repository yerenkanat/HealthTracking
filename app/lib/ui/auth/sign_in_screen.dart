/// Phone-OTP sign-in — enter a number, then the code sent to it. Driven by the
/// pure PhoneAuthController (domain/phone_auth.dart), so all the flow logic is
/// unit-tested; this is just its face.
///
/// Works today against the stub provider (test code 123456) and unchanged
/// against Firebase once wired. On success it calls [onSignedIn] with the
/// session; the caller stores and persists it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/phone_auth.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class SignInScreen extends StatefulWidget {
  /// The auth provider — StubPhoneAuthProvider today, Firebase later.
  final PhoneAuthProvider provider;
  final ValueChanged<AuthSession> onSignedIn;
  const SignInScreen({super.key, required this.provider, required this.onSignedIn});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phone = TextEditingController(text: '+7');
  final _code = TextEditingController();
  late final PhoneAuthController controller;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    controller = PhoneAuthController(
      provider: widget.provider,
      onChange: () {
        if (!mounted) return;
        if (controller.isSignedIn && !_notified) {
          _notified = true;
          widget.onSignedIn(controller.session!);
        }
        setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _errorText(L10nLike l) {
    final code = controller.errorCode;
    if (code == null) return null;
    return l.t('auth_err_$code');
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = controller;
    final onCode = c.step == AuthStep.code;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(l.t('auth_title')),
        leading: onCode
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l.t('auth_back'),
                onPressed: c.busy ? null : c.editPhone,
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(onCode ? l.t('auth_code_intro', {'phone': c.session?.phoneE164 ?? _phone.text}) : l.t('auth_phone_intro'),
              style: const TextStyle(color: Palette.textDim, fontSize: 14, height: 1.45)),
          const SizedBox(height: 20),
          if (!onCode) ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
              decoration: InputDecoration(
                labelText: l.t('auth_phone_label'),
                hintText: '+7 700 000 00 00',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              onSubmitted: (_) => _submitPhone(),
            ),
          ] else ...[
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofocus: true,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l.t('auth_code_label'),
                hintText: '000000',
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              onSubmitted: (_) => _submitCode(),
            ),
          ],
          if (_errorText(l) != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: Palette.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(_errorText(l)!, style: const TextStyle(color: Palette.danger, fontSize: 13))),
            ]),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: c.busy ? null : (onCode ? _submitCode : _submitPhone),
            child: c.busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(onCode ? l.t('auth_verify') : l.t('auth_send_code')),
          ),
        ],
      ),
    );
  }

  void _submitPhone() => controller.submitPhone(_phone.text);
  void _submitCode() => controller.submitCode(_code.text);
}

/// Minimal structural type so `_errorText` reads without importing the full L10n.
typedef L10nLike = dynamic;
