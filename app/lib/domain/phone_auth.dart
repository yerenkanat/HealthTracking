/// Phone-OTP sign-in — the flow that turns the phone number the app already
/// collects into an authenticated session with a stable `userId` and a token to
/// send on every request.
///
/// PURE Dart → verified by tool/verify_phone_auth.dart.
///
/// WHY THIS EXISTS
///
/// The audit's root blocker: nothing signs in. Every "authenticated" call falls
/// back to a forgeable `x-user-id` dev header, so no data can be tied to a real
/// account and none of the backend CRUD/sync endpoints can be used safely.
///
/// This is deliberately PROVIDER-AGNOSTIC. The real implementation will be
/// Firebase phone auth (needs a project + credentials, see BACKLOG); until those
/// keys arrive, [StubPhoneAuthProvider] runs the exact same flow deterministically
/// so the screen, the persistence and the request plumbing can all be built and
/// tested now. Swapping in Firebase later changes ONE class, not the flow.
library;

/// A signed-in session. Persisted so a sign-in survives a restart; the [token]
/// is what the HTTP transport sends (as the bearer / id token) once real auth is
/// wired.
class AuthSession {
  /// Stable per-account id. Derived from the phone by the stub; issued by the
  /// backend under real auth. This is the id the app sends and keys data on.
  final String userId;
  final String phoneE164;
  final String token;
  final DateTime signedInAt;

  const AuthSession({
    required this.userId,
    required this.phoneE164,
    required this.token,
    required this.signedInAt,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'phoneE164': phoneE164,
        'token': token,
        'signedInAt': signedInAt.toIso8601String(),
      };

  /// Tolerant: a session missing a required field is treated as "not signed in"
  /// (null) rather than throwing — a corrupt entry should cost the session, not
  /// crash the launch.
  static AuthSession? fromJson(Map<String, dynamic> j) {
    final userId = j['userId'] as String?;
    final phone = j['phoneE164'] as String?;
    final token = j['token'] as String?;
    final at = DateTime.tryParse((j['signedInAt'] as String?) ?? '');
    if (userId == null || userId.isEmpty || phone == null || token == null || at == null) {
      return null;
    }
    return AuthSession(userId: userId, phoneE164: phone, token: token, signedInAt: at);
  }
}

/// An in-flight OTP challenge — the opaque id the provider gave back when the
/// code was requested, plus the phone it was for.
class OtpChallenge {
  final String verificationId;
  final String phoneE164;
  const OtpChallenge({required this.verificationId, required this.phoneE164});
}

/// A failure with a stable, localizable [code] so the UI can explain it without
/// parsing English. Codes: 'invalid-phone', 'invalid-code', 'network'.
class AuthException implements Exception {
  final String code;
  const AuthException(this.code);
  @override
  String toString() => 'AuthException($code)';
}

/// A 6-digit numeric one-time code.
bool isValidOtp(String code) => RegExp(r'^\d{6}$').hasMatch(code.trim());

/// An E.164 phone: a '+' and 8–15 digits.
bool isValidE164(String phone) => RegExp(r'^\+\d{8,15}$').hasMatch(phone.trim());

/// Provider-agnostic phone-OTP auth. Firebase implements this later; the stub
/// implements it now.
abstract interface class PhoneAuthProvider {
  /// Send a code to [phoneE164]; returns a challenge to verify against.
  /// Throws [AuthException]('invalid-phone') for a malformed number.
  Future<OtpChallenge> requestCode(String phoneE164);

  /// Verify [code] against [challenge]; returns a session or throws
  /// [AuthException]('invalid-code').
  Future<AuthSession> verifyCode(OtpChallenge challenge, String code);
}

/// A deterministic, offline stand-in for real phone auth, so the whole flow is
/// exercisable without a Firebase project. It accepts [testCode] (default
/// '123456') for any validly-formed phone and refuses anything else. The
/// [userId] is a stable function of the phone, so the same number always maps to
/// the same account across restarts — exactly what real auth guarantees.
class StubPhoneAuthProvider implements PhoneAuthProvider {
  final String testCode;
  final DateTime Function() now;
  const StubPhoneAuthProvider({this.testCode = '123456', required this.now});

  @override
  Future<OtpChallenge> requestCode(String phoneE164) async {
    final phone = phoneE164.trim();
    if (!isValidE164(phone)) throw const AuthException('invalid-phone');
    // The "verification id" a real provider would hand back; here it just
    // echoes the phone so verifyCode is self-contained.
    return OtpChallenge(verificationId: 'stub:$phone', phoneE164: phone);
  }

  @override
  Future<AuthSession> verifyCode(OtpChallenge challenge, String code) async {
    if (!isValidOtp(code) || code.trim() != testCode) {
      throw const AuthException('invalid-code');
    }
    final uid = stubUserIdFor(challenge.phoneE164);
    return AuthSession(
      userId: uid,
      phoneE164: challenge.phoneE164,
      token: 'stub-token:$uid',
      signedInAt: now(),
    );
  }
}

/// Stable, deterministic id for a phone under the stub — a small FNV-1a hash of
/// the digits, so it is short, opaque, and identical on every run. Never used
/// under real auth (the backend issues the id then).
String stubUserIdFor(String phoneE164) {
  const prime = 0x01000193;
  var hash = 0x811c9dc5;
  for (final unit in phoneE164.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * prime) & 0xffffffff;
  }
  return 'u_${hash.toRadixString(16).padLeft(8, '0')}';
}

/// Where the sign-in screen is in the flow.
enum AuthStep { phone, code, done }

/// Drives the sign-in screen: phone → code → session. Pure (no Flutter) so the
/// verify runner exercises every transition. [onChange] is called after each
/// state change so a UI can rebuild.
class PhoneAuthController {
  final PhoneAuthProvider provider;
  final void Function()? onChange;

  PhoneAuthController({required this.provider, this.onChange});

  AuthStep step = AuthStep.phone;
  bool busy = false;
  String? errorCode; // last AuthException code, cleared on the next action
  OtpChallenge? _challenge;
  AuthSession? session;

  bool get isSignedIn => session != null;

  void _emit() => onChange?.call();

  /// Request a code for [phoneE164]. On success advances to the code step.
  Future<void> submitPhone(String phoneE164) async {
    if (busy) return;
    errorCode = null;
    if (!isValidE164(phoneE164.trim())) {
      errorCode = 'invalid-phone';
      _emit();
      return;
    }
    busy = true;
    _emit();
    try {
      _challenge = await provider.requestCode(phoneE164.trim());
      step = AuthStep.code;
    } on AuthException catch (e) {
      errorCode = e.code;
    } catch (_) {
      errorCode = 'network';
    } finally {
      busy = false;
      _emit();
    }
  }

  /// Verify [code] against the pending challenge. On success stores the session
  /// and advances to done.
  Future<void> submitCode(String code) async {
    if (busy || _challenge == null) return;
    errorCode = null;
    if (!isValidOtp(code.trim())) {
      errorCode = 'invalid-code';
      _emit();
      return;
    }
    busy = true;
    _emit();
    try {
      session = await provider.verifyCode(_challenge!, code.trim());
      step = AuthStep.done;
    } on AuthException catch (e) {
      errorCode = e.code;
    } catch (_) {
      errorCode = 'network';
    } finally {
      busy = false;
      _emit();
    }
  }

  /// Re-request a code for the same number (the SMS never arrived). Stays on the
  /// code step; a new challenge replaces the old.
  Future<void> resendCode() async {
    final ch = _challenge;
    if (busy || ch == null) return;
    errorCode = null;
    busy = true;
    _emit();
    try {
      _challenge = await provider.requestCode(ch.phoneE164);
    } on AuthException catch (e) {
      errorCode = e.code;
    } catch (_) {
      errorCode = 'network';
    } finally {
      busy = false;
      _emit();
    }
  }

  /// Go back to editing the phone (e.g. wrong number), discarding the challenge.
  void editPhone() {
    _challenge = null;
    errorCode = null;
    step = AuthStep.phone;
    _emit();
  }
}
