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

  @override
  bool get requiresCode => false;

  @override
  Future<OtpChallenge> requestCode(String phoneE164) async {
    // Nothing is sent, so this only checks the shape. Doing the sign-in here
    // instead would mean a number is claimed the moment somebody types it and
    // then backs out.
    final phone = phoneE164.trim();
    if (!isValidE164(phone)) throw const AuthException('invalid-phone');
    return OtpChallenge(verificationId: 'server:$phone', phoneE164: phone);
  }

  @override
  Future<AuthSession> verifyCode(OtpChallenge challenge, String code) async {
    final uri = Uri.parse('$baseUrl/auth/phone');
    late final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'phone': challenge.phoneE164}),
          )
          .timeout(timeout);
    } catch (_) {
      // Every transport failure is one thing to the person holding the phone:
      // it did not work and it is not their fault.
      throw const AuthException('network');
    }

    if (res.statusCode == 429) throw const AuthException('too-many-attempts');
    if (res.statusCode == 400) throw const AuthException('invalid-phone');
    if (res.statusCode != 200) throw const AuthException('network');

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AuthException('network');
    }

    final userId = body['userId'] as String?;
    final token = body['token'] as String?;
    // A 200 that carries no token is not a sign-in. Accepting it would store a
    // session that authenticates nothing and fail later, somewhere unrelated.
    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      throw const AuthException('network');
    }

    return AuthSession(
      userId: userId,
      phoneE164: (body['phone'] as String?) ?? challenge.phoneE164,
      token: token,
      signedInAt: now(),
    );
  }
}
