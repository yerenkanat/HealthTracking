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

/// How far she got in one lesson.
///
/// Kept by the server against her PHONE, so a reinstall or a new device finds
/// its place again. Thirty lessons with no memory of any of them is a course
/// nobody finishes.
class LessonProgress {
  final String lessonId;
  final int positionSeconds;

  /// YouTube's, as the player measured it. Null until a player has loaded the
  /// video once, so the bar cannot be drawn from the first tap.
  final int? durationSeconds;
  final bool completed;

  const LessonProgress({
    required this.lessonId,
    this.positionSeconds = 0,
    this.durationSeconds,
    this.completed = false,
  });

  /// 0..1, or null when the length is not known yet — which draws no bar at all
  /// rather than a full or empty one, both of which would be a lie.
  double? get fraction {
    final d = durationSeconds;
    if (completed) return 1;
    if (d == null || d <= 0) return null;
    return (positionSeconds / d).clamp(0.0, 1.0);
  }

  /// Worth offering to resume. Under a minute is where she was still deciding
  /// whether to watch, and "continue from 0:12" is noise.
  bool get resumable => !completed && positionSeconds >= 60;

  static LessonProgress? fromJson(Map<String, dynamic> j) {
    final id = j['lessonId'] as String?;
    if (id == null || id.isEmpty) return null;
    return LessonProgress(
      lessonId: id,
      positionSeconds: (j['positionSeconds'] as num?)?.toInt() ?? 0,
      durationSeconds: (j['durationSeconds'] as num?)?.toInt(),
      completed: j['completed'] == true,
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

  /// One entry per lesson she has opened, keyed by lesson id. Sent with the
  /// lessons in the same response so nothing paints as unwatched first.
  final Map<String, LessonProgress> progress;

  const CourseAccess({
    required this.entitled,
    required this.lessons,
    this.progress = const {},
  });

  /// The lesson to offer as "continue" — the one she was last in the middle of,
  /// or the first she has not finished. Null when she has finished everything,
  /// which is the one case where there is nothing to continue.
  CourseLesson? get resume {
    for (final l in lessons) {
      if (progress[l.id]?.resumable == true) return l;
    }
    for (final l in lessons) {
      if (progress[l.id]?.completed != true) return l;
    }
    return null;
  }

  int get completedCount =>
      lessons.where((l) => progress[l.id]?.completed == true).length;

  static CourseAccess fromJson(Map<String, dynamic> j) {
    final raw = (j['lessons'] as List?) ?? const [];
    final lessons = raw
        .whereType<Map<String, dynamic>>()
        .map(CourseLesson.fromJson)
        .whereType<CourseLesson>()
        .toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));

    final progress = <String, LessonProgress>{};
    for (final p in ((j['progress'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LessonProgress.fromJson)
        .whereType<LessonProgress>()) {
      progress[p.lessonId] = p;
    }
    return CourseAccess(
        entitled: j['entitled'] == true, lessons: lessons, progress: progress);
  }

  /// The same course with one lesson's progress replaced — what the list is
  /// rebuilt from when she comes back from the player, so the tick appears
  /// without a round trip.
  CourseAccess withProgress(LessonProgress p) => CourseAccess(
        entitled: entitled,
        lessons: lessons,
        progress: {...progress, p.lessonId: p},
      );

  static const none = CourseAccess(entitled: false, lessons: []);
}
