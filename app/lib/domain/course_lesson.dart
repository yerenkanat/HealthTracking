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

/// One lesson as somebody who has NOT bought the course sees it — screen 34.
///
/// Titles and summaries, and a video only on the free one. The server strips
/// the rest; this models what arrives rather than deciding anything, because a
/// client that decided what was free would be a paywall anyone can edit.
class CoursePreviewLesson {
  final String id;
  final String titleRu;
  final String? titleKk;
  final String? summaryRu;
  final String? summaryKk;
  final int sort;

  /// Playable without buying. Comes from the server.
  final bool free;

  /// Present only when [free]. Absent on a locked lesson, which is the point.
  final String? youtubeUrl;

  const CoursePreviewLesson({
    required this.id,
    required this.titleRu,
    required this.sort,
    required this.free,
    this.titleKk,
    this.summaryRu,
    this.summaryKk,
    this.youtubeUrl,
  });

  /// The title for [languageCode], falling back to Russian. Same signature as
  /// [CourseLesson.title] on purpose — two shapes for one question is how a
  /// caller ends up passing the wrong one and never noticing.
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

  static CoursePreviewLesson? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final titleRu = j['titleRu'] as String?;
    if (id == null || titleRu == null || titleRu.isEmpty) return null;
    final free = j['free'] == true;
    final url = j['youtubeUrl'] as String?;
    return CoursePreviewLesson(
      id: id,
      titleRu: titleRu,
      titleKk: j['titleKk'] as String?,
      summaryRu: j['summaryRu'] as String?,
      summaryKk: j['summaryKk'] as String?,
      sort: (j['sort'] as num?)?.toInt() ?? 0,
      free: free,
      // Belt and braces: even if a future server sent a URL on a locked
      // lesson, this build will not carry one into the player.
      youtubeUrl: free ? url : null,
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
///
/// [checkFailed] is the third fact, and the same argument again: "the server
/// said no" and "the server said nothing" are not the same answer. Reading a
/// failed request as `entitled: false` showed the sales pitch for the course to
/// a woman who had paid 39 000 ₸ for it, every time her train went into a
/// tunnel. This state asserts NOTHING about what she owns, and the screens that
/// receive it are required to assert nothing either.
class CourseAccess {
  final bool entitled;
  final List<CourseLesson> lessons;

  /// True only on [unknown]: nobody answered, so neither branch may be drawn.
  /// Never set from a parsed response — a response IS an answer.
  final bool checkFailed;

  /// What the course contains, for somebody who has not bought it. Empty when
  /// she owns it — the real [lessons] are the list then.
  final List<CoursePreviewLesson> preview;

  /// One entry per lesson she has opened, keyed by lesson id. Sent with the
  /// lessons in the same response so nothing paints as unwatched first.
  final Map<String, LessonProgress> progress;

  const CourseAccess({
    required this.entitled,
    required this.lessons,
    this.progress = const {},
    this.preview = const [],
    this.checkFailed = false,
  }) :
        // An unanswered check cannot unlock anything: that would be the client
        // granting itself the entitlement the server exists to decide.
        assert(!(checkFailed && entitled));

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
      entitled: j['entitled'] == true,
      lessons: lessons,
      progress: progress,
      preview: [
        for (final p in ((j['preview'] as List?) ?? const []))
          if (p is Map<String, dynamic>)
            if (CoursePreviewLesson.fromJson(p) case final v?) v,
      ]..sort((a, b) => a.sort.compareTo(b.sort)),
    );
  }

  /// The same course with one lesson's progress replaced — what the list is
  /// rebuilt from when she comes back from the player, so the tick appears
  /// without a round trip.
  CourseAccess withProgress(LessonProgress p) => CourseAccess(
        entitled: entitled,
        lessons: lessons,
        preview: preview,
        progress: {...progress, p.lessonId: p},
        checkFailed: checkFailed,
      );

  /// The server said she has not bought it. An offer.
  static const none = CourseAccess(entitled: false, lessons: []);

  /// Nobody said anything — the request threw, timed out, or came back
  /// unreadable. NOT an offer and NOT a course: see [checkFailed].
  ///
  /// Deliberately not persisted anywhere. A cached "entitled" would outlive a
  /// refund and would be a paywall the client enforces (`ApiClient.getCourse`
  /// says why that is worthless), and it would have to carry the lesson videos
  /// — the paid goods themselves — onto the disk of somebody who may not own
  /// them. A cached "not entitled" is the defect this state exists to kill:
  /// it would show the pitch to a buyer whose only sin was a dead network.
  /// What IS kept is the answer already received in this session, in memory,
  /// by the screens below: a refresh that fails does not demote a course she
  /// is in the middle of watching.
  static const unknown =
      CourseAccess(entitled: false, lessons: [], checkFailed: true);
}
