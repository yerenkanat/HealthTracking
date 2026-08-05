/// The Ма!Ма! course — the lessons that come with the комплект.
///
/// The combo costs 39 000 ₸ against 29 800 for the two devices alone, and the
/// difference IS this course. So whether these appear is not a display choice:
/// it is what somebody paid for. The server decides (GET /course/lessons
/// answers `entitled`), and this file only models what it sends.
///
/// PURE Dart — no Flutter — so the parsing is testable without a widget.
library;

class CourseLesson {
  final String id;
  final String titleRu;

  /// Optional. Lessons go up in Russian first and blocking one until it is
  /// translated would mean nothing ships, so the Kazakh reader falls back to
  /// the Russian title rather than seeing a gap.
  final String? titleKk;
  final String youtubeUrl;
  final String? summaryRu;
  final String? summaryKk;
  final int sort;

  const CourseLesson({
    required this.id,
    required this.titleRu,
    required this.youtubeUrl,
    this.titleKk,
    this.summaryRu,
    this.summaryKk,
    this.sort = 0,
  });

  /// The title for [languageCode], falling back to Russian.
  String title(String languageCode) {
    if (languageCode == 'kk') {
      final kk = titleKk?.trim();
      if (kk != null && kk.isNotEmpty) return kk;
    }
    return titleRu;
  }

  String? summary(String languageCode) {
    if (languageCode == 'kk') {
      final kk = summaryKk?.trim();
      if (kk != null && kk.isNotEmpty) return kk;
    }
    final ru = summaryRu?.trim();
    return (ru == null || ru.isEmpty) ? null : ru;
  }

  /// Tolerant: a lesson missing an id, a title or a link is dropped rather than
  /// thrown, because one malformed row must not empty the whole course for
  /// somebody who paid for it.
  static CourseLesson? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final title = (j['titleRu'] as String?)?.trim();
    final url = (j['youtubeUrl'] as String?)?.trim();
    if (id == null || id.isEmpty) return null;
    if (title == null || title.isEmpty) return null;
    if (url == null || url.isEmpty) return null;
    return CourseLesson(
      id: id,
      titleRu: title,
      titleKk: j['titleKk'] as String?,
      youtubeUrl: url,
      summaryRu: j['summaryRu'] as String?,
      summaryKk: j['summaryKk'] as String?,
      sort: (j['sort'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What the server said about the course: whether this account owns it, and the
/// lessons if so.
///
/// [entitled] is carried separately from `lessons.isEmpty` on purpose. "You have
/// not bought this" and "the course has no lessons yet" need different screens —
/// one is an offer, the other is an apology — and collapsing them into an empty
/// list would show the wrong one half the time.
class CourseAccess {
  final bool entitled;
  final List<CourseLesson> lessons;
  const CourseAccess({required this.entitled, required this.lessons});

  static CourseAccess fromJson(Map<String, dynamic> j) {
    final raw = (j['lessons'] as List?) ?? const [];
    final lessons = raw
        .whereType<Map<String, dynamic>>()
        .map(CourseLesson.fromJson)
        .whereType<CourseLesson>()
        .toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return CourseAccess(entitled: j['entitled'] == true, lessons: lessons);
  }

  static const none = CourseAccess(entitled: false, lessons: []);
}
