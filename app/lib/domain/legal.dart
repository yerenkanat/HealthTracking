/// The version of the legal documents (privacy policy + terms) a user must have
/// accepted. Bump this whenever the meaning of those documents changes; the app
/// then re-prompts anyone who accepted an older version before letting them back
/// in. A store listing and GDPR both require that consent be recorded and
/// re-obtained on a material change — a one-time checkbox that evaporates on
/// restart is not enough.
///
/// PURE Dart → covered by verify_persistence.dart (round-trip) and the app gate.
library;

/// Current legal-document version. Increment on any material change to the
/// privacy policy or terms (see lib/ui/settings/legal_screen.dart).
const int currentLegalVersion = 1;

/// Whether a user who last accepted [acceptedVersion] must accept again.
bool legalConsentNeeded(int acceptedVersion) => acceptedVersion < currentLegalVersion;
