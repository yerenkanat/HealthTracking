/// Phone sign-in against our own backend.
///
/// The real implementation of [PhoneAuthProvider], replacing the stub that
/// accepted 123456 on the handset and never spoke to anyone. With the stub, an
/// account existed only on the phone that made it: reinstall the app and the
/// pregnancy was gone.
///
/// One call: `POST /auth/phone` with the number, back comes a user id and a
/// bearer token that every later request carries. Registering and signing in
/// are the same request, because there is no separate register screen and
/// asking a tired person to remember which she did last time would be a worse
/// product.
///
/// There is no SMS, so [requiresCode] is false and the code screen is skipped.
/// The number is CLAIMED, not verified — see the server's routes/phoneAuth.ts
/// for what that does and does not protect. When a gateway is added, the server
/// starts requiring a code and this flips to true; the code screen is already
/// written and tested.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../domain/phone_auth.dart';

class ServerPhoneAuthProvider implements PhoneAuthProvider {
  /// e.g. `https://ana-bala.kz`. No path — see http_transport.dart.
  final String baseUrl;
  final DateTime Function() now;
  final http.Client _client;

  /// Bounded so a dead network cannot leave the sign-in button spinning for
  /// ever, which is what an unbounded future does to this screen.
  final Duration timeout;

  ServerPhoneAuthProvider({
    required this.baseUrl,
    required this.now,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  /// Set from the server's answer to [requestCode].
  ///
  /// The SERVER decides whether a code is needed, not a compile-time flag in
  /// here: there is no SMS gateway today, and when one is added the switch is
  /// thrown on the backend and this app follows on the next sign-in — no
  /// release, no version of the app left demanding a code nobody sends.
  bool _codeRequired = false;

  /// The session minted during [requestCode] when no code was required. Held
  /// for one step only, then handed to the caller and cleared.
  AuthSession? _immediate;

  @override
  bool get requiresCode => _codeRequired;

  @override
  Future<OtpChallenge> requestCode(String phoneE164) async {
    final phone = phoneE164.trim();
    if (!isValidE164(phone)) throw const AuthException('invalid-phone');

    late final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$baseUrl/auth/phone/start'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'phone': phone}),
          )
          .timeout(timeout);
    } catch (_) {
      throw const AuthException('network');
    }

    if (res.statusCode == 429) throw const AuthException('too-many-attempts');
    if (res.statusCode == 400) throw const AuthException('invalid-phone');
    // No gateway configured, or it refused the message. Distinct from a network
    // failure on purpose: nothing is coming, so "check your signal" would send
    // her to wait for a message that was never sent.
    if (res.statusCode == 503) throw const AuthException('sms-unavailable');
    if (res.statusCode != 200) throw const AuthException('network');

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AuthException('network');
    }

    // No code needed: the session came back with this very answer, so there is
    // nothing to type and nothing to wait for.
    _codeRequired = body['codeRequired'] == true;
    _immediate = _codeRequired ? null : _sessionFrom(body, phone);
    if (!_codeRequired && _immediate == null) {
      // codeRequired:false with no session is not a sign-in. Accepting it would
      // strand her on a code screen for a code that is never coming.
      throw const AuthException('network');
    }

    return OtpChallenge(verificationId: 'server:$phone', phoneE164: phone);
  }

  @override
  Future<AuthSession> verifyCode(OtpChallenge challenge, String code) async {
    // Already signed in during the first step, because the server asked for no
    // code. The screen still calls this, so hand it back here rather than
    // making the screen know which mode it is in.
    final ready = _immediate;
    if (ready != null) {
      _immediate = null;
      return ready;
    }

    final uri = Uri.parse('$baseUrl/auth/phone/verify');
    late final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'phone': challenge.phoneE164, 'code': code.trim()}),
          )
          .timeout(timeout);
    } catch (_) {
      // Every transport failure is one thing to the person holding the phone:
      // it did not work and it is not their fault.
      throw const AuthException('network');
    }

    if (res.statusCode == 429) throw const AuthException('too-many-attempts');
    if (res.statusCode == 400) throw const AuthException('invalid-code');
    if (res.statusCode == 401) {
      // Which of the three it is changes what she should do next, so it is not
      // collapsed into one message.
      final err = _errorOf(res.body);
      throw AuthException(err == 'too_many_attempts'
          ? 'too-many-attempts'
          : err == 'code_expired'
              ? 'code-expired'
              : 'invalid-code');
    }
    if (res.statusCode != 200) throw const AuthException('network');

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AuthException('network');
    }

    final session = _sessionFrom(body, challenge.phoneE164);
    if (session == null) throw const AuthException('network');
    return session;
  }

  /// A session from a server answer, or null when it does not carry one.
  ///
  /// A 200 with no token is not a sign-in. Accepting it would store a session
  /// that authenticates nothing and fail later, somewhere unrelated.
  AuthSession? _sessionFrom(Map<String, dynamic> body, String fallbackPhone) {
    final userId = body['userId'] as String?;
    final token = body['token'] as String?;
    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return AuthSession(
      userId: userId,
      phoneE164: (body['phone'] as String?) ?? fallbackPhone,
      token: token,
      signedInAt: now(),
    );
  }
}

/// The `error` field of a JSON body, or empty when there is not one.
///
/// Tolerant on purpose: this runs on an error path, and failing to parse the
/// explanation of a failure must not replace it with a crash.
String _errorOf(String body) {
  try {
    final j = jsonDecode(body);
    return j is Map && j['error'] is String ? j['error'] as String : '';
  } catch (_) {
    return '';
  }
}
