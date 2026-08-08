/// Screen 40 — «Семейный доступ».
///
/// Who the mother has let in, at what level, and the links that are still
/// good. Parsing and formatting only: the server decides what a level may
/// reach, and re-deciding it here would be a second answer to the question
/// that matters most on this screen.
library;

/// What a relative may do. Mirrors ACCESS_LEVELS on the server.
enum AccessLevel { viewer, guardian }

AccessLevel? accessLevelFrom(String? wire) => switch (wire) {
      'viewer' => AccessLevel.viewer,
      'guardian' => AccessLevel.guardian,
      // A level this build does not know is a server newer than the app.
      // Dropping the row beats guessing at what somebody can see.
      _ => null,
    };

extension AccessLevelWire on AccessLevel {
  String get wire => this == AccessLevel.viewer ? 'viewer' : 'guardian';
  String get l10nKey =>
      this == AccessLevel.viewer ? 'fam_level_viewer' : 'fam_level_guardian';
  String get descriptionKey =>
      this == AccessLevel.viewer ? 'fam_level_viewer_hint' : 'fam_level_guardian_hint';
}

/// Somebody who has been let in.
class FamilyMember {
  final String memberUserId;

  /// What the mother calls them — «Папа», «Бабушка». Hers, not their profile
  /// name, because this list is read by her.
  final String label;

  /// Their own name, once they have accepted and filled one in.
  final String? displayName;
  final String? phone;
  final AccessLevel level;
  final DateTime? since;

  const FamilyMember({
    required this.memberUserId,
    required this.label,
    required this.level,
    this.displayName,
    this.phone,
    this.since,
  });

  /// What to show. Her label wins over their profile name — she wrote it, and
  /// «Папа» is more use to her at a glance than «Ерлан Ж.».
  String get title =>
      label.trim().isNotEmpty ? label.trim() : (displayName ?? phone ?? '');

  static FamilyMember? fromJson(Map<String, dynamic> j) {
    final level = accessLevelFrom(j['level'] as String?);
    final id = j['memberUserId'] as String?;
    if (level == null || id == null || id.isEmpty) return null;
    return FamilyMember(
      memberUserId: id,
      label: (j['label'] as String?) ?? '',
      displayName: (j['displayName'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['displayName'] as String,
      phone: (j['phone'] as String?)?.trim().isEmpty ?? true ? null : j['phone'] as String,
      level: level,
      since: DateTime.tryParse('${j['createdAt']}')?.toLocal(),
    );
  }
}

/// A link that has been created and not yet used.
class FamilyInvite {
  /// Identifies the invitation for revoking. NOT the token — that was shown
  /// once when it was made and the server cannot give it back.
  final String tokenHash;
  final AccessLevel level;
  final String label;
  final DateTime expiresAt;

  const FamilyInvite({
    required this.tokenHash,
    required this.level,
    required this.label,
    required this.expiresAt,
  });

  static FamilyInvite? fromJson(Map<String, dynamic> j) {
    final level = accessLevelFrom(j['level'] as String?);
    final expires = DateTime.tryParse('${j['expiresAt']}');
    final hash = j['tokenHash'] as String?;
    if (level == null || expires == null || hash == null) return null;
    return FamilyInvite(
      tokenHash: hash,
      level: level,
      label: (j['label'] as String?) ?? '',
      expiresAt: expires.toLocal(),
    );
  }

  /// Hours left, rounded up, never below zero. The server has already dropped
  /// expired links; this is for the countdown on the card.
  int hoursLeft(DateTime now) {
    final ms = expiresAt.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 3600000).ceil();
  }
}

/// Whose children I can see — the other direction.
class FamilyMembership {
  final String ownerUserId;
  final AccessLevel level;
  const FamilyMembership({required this.ownerUserId, required this.level});

  static FamilyMembership? fromJson(Map<String, dynamic> j) {
    final level = accessLevelFrom(j['level'] as String?);
    final id = j['ownerUserId'] as String?;
    if (level == null || id == null) return null;
    return FamilyMembership(ownerUserId: id, level: level);
  }
}

class FamilyAccess {
  final List<FamilyMember> members;
  final List<FamilyInvite> invites;
  final List<FamilyMembership> memberships;

  /// What a grant can ever cover, from the server. The green banner is drawn
  /// from this rather than from a sentence typed into the screen, so if the
  /// server ever started sharing something of the mother's the banner would
  /// stop claiming otherwise.
  final List<String> shareable;

  const FamilyAccess({
    this.members = const [],
    this.invites = const [],
    this.memberships = const [],
    this.shareable = const [],
  });

  /// True when nothing the server will share is the mother's own.
  ///
  /// The condition behind «здоровье и цикл не видит никто». If it is ever
  /// false the banner is not shown — a promise that has stopped being true
  /// must not keep being made.
  bool get sharesOnlyChildData =>
      shareable.isNotEmpty && shareable.every((s) => s.startsWith('child_'));

  static FamilyAccess fromJson(Map<String, dynamic> j) => FamilyAccess(
        members: [
          for (final m in (j['members'] as List? ?? const []))
            if (m is Map<String, dynamic>)
              if (FamilyMember.fromJson(m) case final v?) v,
        ],
        invites: [
          for (final i in (j['invites'] as List? ?? const []))
            if (i is Map<String, dynamic>)
              if (FamilyInvite.fromJson(i) case final v?) v,
        ],
        memberships: [
          for (final m in (j['memberships'] as List? ?? const []))
            if (m is Map<String, dynamic>)
              if (FamilyMembership.fromJson(m) case final v?) v,
        ],
        shareable: [
          for (final s in (j['shareable'] as List? ?? const []))
            if (s is String) s,
        ],
      );
}

/// Why an invitation was refused. Each needs different words: an expired link
/// needs a new one, a used one probably means somebody else already joined.
String inviteRefusalKey(String? reason) => switch (reason) {
      'expired' => 'fam_refused_expired',
      'already_used' => 'fam_refused_used',
      'revoked' => 'fam_refused_revoked',
      'own_invite' => 'fam_refused_own',
      _ => 'fam_refused_unknown',
    };
