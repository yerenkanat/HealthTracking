/// A рассылка, as it lands on her phone — the app half of admin frame 06.
///
/// Somebody in the back office writes one message to a chosen group of mothers
/// («беременные», «мамы детей до года», «только қазақша»). This is what arrives.
///
/// TWO LANGUAGES TRAVEL, always. She may switch the app to Kazakh a week after
/// the message arrives, and a copy cached in the language she used to read is a
/// bug she cannot fix from inside the app. The server refuses to publish a
/// broadcast without the Kazakh half for the same reason, so both halves are
/// real text rather than one of them being a placeholder.
///
/// PURE Dart: no Flutter, no shared_preferences. The parsing and the language
/// choice are the two things most likely to be wrong, and both are testable
/// without a widget.
library;

/// One language's copy of the message.
class AnnouncementText {
  final String title;
  final String body;
  const AnnouncementText({required this.title, required this.body});

  factory AnnouncementText.fromJson(Map<String, dynamic> j) => AnnouncementText(
        title: (j['title'] as String?)?.trim() ?? '',
        body: (j['body'] as String?)?.trim() ?? '',
      );

  Map<String, dynamic> toJson() => {'title': title, 'body': body};

  /// Empty means "this language has nothing to show", not "this message is
  /// blank" — [Announcement.textFor] falls back rather than painting nothing.
  bool get isEmpty => title.isEmpty && body.isEmpty;
}

class Announcement {
  /// The broadcast id. Stable, so the same message read twice is one row.
  final String id;

  /// When it was sent TO HER — the delivery row, not the publication instant.
  /// Two women in different weekly windows can honestly see different times.
  final DateTime at;

  final AnnouncementText ru;
  final AnnouncementText kk;

  const Announcement({
    required this.id,
    required this.at,
    required this.ru,
    required this.kk,
  });

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: (j['id'] as String?)?.trim() ?? '',
        at: DateTime.parse(j['at'] as String).toLocal(),
        ru: AnnouncementText.fromJson(((j['ru'] as Map?) ?? const {}).cast<String, dynamic>()),
        kk: AnnouncementText.fromJson(((j['kk'] as Map?) ?? const {}).cast<String, dynamic>()),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'ru': ru.toJson(),
        'kk': kk.toJson(),
      };

  /// The copy for a locale code ('ru' | 'kk' | 'en').
  ///
  /// `en` → ru, like the pregnancy calendar: the back office writes in two
  /// languages and an English-speaking user reading Russian is better off than
  /// one reading an empty card. And an EMPTY Kazakh half falls back too — the
  /// publication gate should make that impossible, but a row written before the
  /// gate existed must not paint a blank notification.
  AnnouncementText textFor(String localeCode) =>
      localeCode == 'kk' && !kk.isEmpty ? kk : ru;

  /// Nothing to show in any language. Dropped on parse rather than rendered as
  /// an empty row she cannot dismiss.
  bool get isEmpty => ru.isEmpty && kk.isEmpty;
}

/// Parse `GET /announcements`.
///
/// Tolerant per row, like the pregnancy calendar: one malformed entry costs
/// that entry, not the whole notification centre — which is also where her
/// child's SOS alerts live.
List<Announcement> parseAnnouncements(Map<String, dynamic> json) {
  final raw = (json['announcements'] as List?) ?? const [];
  final out = <Announcement>[];
  for (final a in raw) {
    if (a is! Map) continue;
    try {
      final parsed = Announcement.fromJson(a.cast<String, dynamic>());
      if (parsed.id.isEmpty || parsed.isEmpty) continue;
      out.add(parsed);
    } catch (_) {
      // skip a bad row
    }
  }
  // Newest first, and de-duplicated by id: the same message must never appear
  // twice because two deliveries were recorded for one person.
  out.sort((a, b) => b.at.compareTo(a.at));
  final seen = <String>{};
  return [for (final a in out) if (seen.add(a.id)) a];
}

/// The bytes to cache — the exact shape [parseAnnouncements] reads back.
Map<String, dynamic> announcementsToJson(List<Announcement> items) =>
    {'announcements': [for (final a in items) a.toJson()]};
