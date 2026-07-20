/// Timeline content — the video lessons and shop products shown for wherever
/// the family currently is: a given week of pregnancy, or a given month of the
/// child's life up to five years.
///
/// PURE Dart, verified by `dart run tool/verify_timeline_content.dart`.
///
/// The catalogue is DATA, not code: [ContentCatalog.fromJson] takes the same
/// shape the backend will serve, so the seeded test content can be swapped for
/// the real thing without touching this file or the UI. Until endpoints exist,
/// `demo_content.dart` supplies a catalogue covering every stage.
library;

/// Where a family is on the timeline.
///
/// Two kinds, deliberately one type: a screen asks "what belongs here?" without
/// caring which half of the app the answer came from.
enum TimelineKind { pregnancyWeek, childMonth }

/// Pregnancy is counted 1..40 by week; childhood 0..60 by month (birth to five
/// years). Content outside these bounds cannot be reached, so the constructors
/// clamp rather than letting a stray value silently match nothing.
const int minPregnancyWeek = 1;
const int maxPregnancyWeek = 40;
const int minChildMonth = 0;
const int maxChildMonth = 60;

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

class TimelineStage {
  final TimelineKind kind;

  /// Week 1..40 for [TimelineKind.pregnancyWeek], month 0..60 for
  /// [TimelineKind.childMonth].
  final int index;

  const TimelineStage._(this.kind, this.index);

  factory TimelineStage.pregnancyWeek(int week) => TimelineStage._(
      TimelineKind.pregnancyWeek, _clamp(week, minPregnancyWeek, maxPregnancyWeek));

  factory TimelineStage.childMonth(int month) =>
      TimelineStage._(TimelineKind.childMonth, _clamp(month, minChildMonth, maxChildMonth));

  /// Stable key used by the catalogue and by the backend: `w20`, `m4`.
  String get key => switch (kind) {
        TimelineKind.pregnancyWeek => 'w$index',
        TimelineKind.childMonth => 'm$index',
      };

  /// Parse a key back. Returns null for anything unrecognised rather than
  /// guessing, so malformed catalogue data is dropped instead of mis-filed.
  static TimelineStage? fromKey(String key) {
    if (key.length < 2) return null;
    final n = int.tryParse(key.substring(1));
    if (n == null) return null;
    return switch (key[0]) {
      'w' => n < minPregnancyWeek || n > maxPregnancyWeek
          ? null
          : TimelineStage.pregnancyWeek(n),
      'm' => n < minChildMonth || n > maxChildMonth ? null : TimelineStage.childMonth(n),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineStage && other.kind == kind && other.index == index;
  @override
  int get hashCode => Object.hash(kind, index);
  @override
  String toString() => key;
}

/// Every stage in order: pregnancy weeks 1..40, then months 0..60. Useful for
/// authoring tools and for checking the catalogue covers the whole timeline.
List<TimelineStage> allTimelineStages() => [
      for (var w = minPregnancyWeek; w <= maxPregnancyWeek; w++) TimelineStage.pregnancyWeek(w),
      for (var m = minChildMonth; m <= maxChildMonth; m++) TimelineStage.childMonth(m),
    ];

enum ContentKind { lesson, product }

/// Text carried per locale, exactly as the backend will send it. Falling back
/// to Russian then English means a partially translated catalogue still shows
/// something rather than a blank card.
class LocalizedText {
  final Map<String, String> byLocale;
  const LocalizedText(this.byLocale);

  String call(String locale) =>
      byLocale[locale] ?? byLocale['ru'] ?? byLocale['en'] ?? '';

  Map<String, dynamic> toJson() => byLocale;
  factory LocalizedText.fromJson(Object? j) => LocalizedText(
        j is Map ? {for (final e in j.entries) '${e.key}': '${e.value}'} : const {},
      );
}

/// One lesson or one product, attached to one stage.
class ContentItem {
  final String id;
  final ContentKind kind;
  final LocalizedText title;
  final LocalizedText summary;

  /// Lessons: where the video plays. Products: where it can be bought.
  /// Empty means "not linked yet" — the UI shows the card without an action
  /// rather than opening a dead link.
  final String url;

  /// Product price in minor units (tiyn), and its currency. Null for lessons.
  /// Integer on purpose: money in floating point invites rounding drift.
  final int? priceMinor;
  final String? currency;

  /// Optional artwork; empty falls back to a generated placeholder.
  final String imageUrl;

  /// Lesson length in minutes, when known.
  final int? durationMin;

  const ContentItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.summary,
    this.url = '',
    this.priceMinor,
    this.currency,
    this.imageUrl = '',
    this.durationMin,
  });

  bool get isLesson => kind == ContentKind.lesson;
  bool get isProduct => kind == ContentKind.product;
  bool get hasLink => url.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title.toJson(),
        'summary': summary.toJson(),
        if (url.isNotEmpty) 'url': url,
        if (priceMinor != null) 'priceMinor': priceMinor,
        if (currency != null) 'currency': currency,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (durationMin != null) 'durationMin': durationMin,
      };

  factory ContentItem.fromJson(Map<String, dynamic> j) => ContentItem(
        id: '${j['id'] ?? ''}',
        kind: j['kind'] == 'product' ? ContentKind.product : ContentKind.lesson,
        title: LocalizedText.fromJson(j['title']),
        summary: LocalizedText.fromJson(j['summary']),
        url: '${j['url'] ?? ''}',
        priceMinor: (j['priceMinor'] as num?)?.toInt(),
        currency: j['currency'] as String?,
        imageUrl: '${j['imageUrl'] ?? ''}',
        durationMin: (j['durationMin'] as num?)?.toInt(),
      );
}

/// Everything published, indexed by stage key.
class ContentCatalog {
  final Map<String, List<ContentItem>> byStage;
  const ContentCatalog(this.byStage);

  static const empty = ContentCatalog({});

  List<ContentItem> itemsFor(TimelineStage stage) => byStage[stage.key] ?? const [];
  List<ContentItem> lessonsFor(TimelineStage stage) =>
      [for (final i in itemsFor(stage)) if (i.isLesson) i];
  List<ContentItem> productsFor(TimelineStage stage) =>
      [for (final i in itemsFor(stage)) if (i.isProduct) i];

  bool hasContentFor(TimelineStage stage) => itemsFor(stage).isNotEmpty;

  /// Stages with nothing published — what an authoring dashboard needs to show.
  List<TimelineStage> missingStages() =>
      [for (final s in allTimelineStages()) if (!hasContentFor(s)) s];

  Map<String, dynamic> toJson() => {
        for (final e in byStage.entries) e.key: [for (final i in e.value) i.toJson()],
      };

  /// Build from the backend's shape. Entries under an unrecognised stage key
  /// are DROPPED rather than kept in a bucket nothing can look up, so bad data
  /// fails visibly in the authoring tools instead of silently never showing.
  factory ContentCatalog.fromJson(Map<String, dynamic> j) {
    final out = <String, List<ContentItem>>{};
    for (final e in j.entries) {
      if (TimelineStage.fromKey(e.key) == null) continue;
      final list = e.value;
      if (list is! List) continue;
      final items = [
        for (final raw in list)
          if (raw is Map) ContentItem.fromJson(raw.cast<String, dynamic>()),
      ];
      if (items.isNotEmpty) out[e.key] = items;
    }
    return ContentCatalog(out);
  }
}

/// Which stage a family is at right now.
///
/// Pregnancy takes precedence: someone who is expecting wants this week's
/// material even if an older child is also tracked. With neither a due date nor
/// a child, there is no stage and the UI shows nothing rather than guessing.
TimelineStage? currentStage({
  required int? gestationWeek,
  required int? childAgeMonths,
}) {
  if (gestationWeek != null && gestationWeek >= minPregnancyWeek) {
    return TimelineStage.pregnancyWeek(gestationWeek);
  }
  if (childAgeMonths != null && childAgeMonths >= minChildMonth) {
    // Past five years the timeline simply ends; showing the last month's
    // content forever would be worse than showing none.
    if (childAgeMonths > maxChildMonth) return null;
    return TimelineStage.childMonth(childAgeMonths);
  }
  return null;
}

/// Formatted price, e.g. 1 290 000 tiyn → "12 900 ₸". Returns empty for a
/// lesson or an unpriced product.
String formatPrice(ContentItem item) {
  final minor = item.priceMinor;
  if (minor == null) return '';
  final major = minor ~/ 100;
  final digits = major.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' '); // nbsp
    buf.write(digits[i]);
  }
  final symbol = switch (item.currency) {
    'KZT' => '₸',
    'USD' => r'$',
    'RUB' => '₽',
    _ => item.currency ?? '',
  };
  return symbol.isEmpty ? buf.toString() : '${buf.toString()} $symbol';
}
