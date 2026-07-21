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

  /// Cities this item is offered in — a product that only ships to Almaty, a
  /// course held in one place. Empty means everywhere, which is the default and
  /// what most items should be.
  final List<String> cities;

  /// Age bounds in years, inclusive. Both null means every age, which again is
  /// the default: these exist for material that is genuinely age-specific, not
  /// as a way to slice the audience.
  final int? minAgeYears;
  final int? maxAgeYears;

  /// Where a lesson's video lives, when it has one.
  ///
  /// Separate from [url] rather than replacing it: [url] still carries a
  /// product's shop page, and a catalogue authored before this field existed
  /// keeps working — see [video], which falls back to it.
  final VideoSource? videoSource;

  /// Other stages this same item also belongs to.
  ///
  /// Most guidance is not specific to one week. A lesson on what to eat in the
  /// second trimester is right for weeks 14 to 27; a baby carrier suits months
  /// 3 to 12. Filed under one stage each, that meant fourteen copies with
  /// fourteen ids — and fourteen places to edit when the video URL changed, of
  /// which someone would miss one.
  ///
  /// The item is authored and STORED once, under its home stage, and listed
  /// under each of these as well. Editing the original edits every appearance,
  /// because there is only one.
  ///
  /// Empty is the default and stays correct for anything genuinely
  /// week-specific ("your baby is the size of a lime this week").
  final List<String> alsoStages;

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
    this.cities = const [],
    this.minAgeYears,
    this.maxAgeYears,
    this.videoSource,
    this.alsoStages = const [],
  });

  /// True when this item is offered everywhere and to every age — the common
  /// case, and the one that never depends on what the profile holds.
  bool get isForEveryone =>
      cities.isEmpty && minAgeYears == null && maxAgeYears == null;

  bool get isLesson => kind == ContentKind.lesson;
  bool get isProduct => kind == ContentKind.product;
  bool get hasLink => url.trim().isNotEmpty;

  /// The video to play for a lesson, or null.
  ///
  /// Falls back to [url] so a catalogue authored before `video` existed still
  /// plays — the provider is inferred from the URL, and anything unrecognised
  /// is treated as external rather than streamed into our own player.
  VideoSource? get video {
    if (videoSource != null && !videoSource!.isEmpty) return videoSource;
    if (!isLesson || url.trim().isEmpty) return null;
    return VideoSource(provider: VideoSource.guessProvider(url), url: url.trim());
  }

  /// Whether tapping this lesson opens our own player rather than leaving the
  /// app. False for products, for unlinked items, and for YouTube.
  bool get playsInApp => video?.playsInline ?? false;

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
        if (cities.isNotEmpty) 'cities': cities,
        if (minAgeYears != null) 'minAgeYears': minAgeYears,
        if (maxAgeYears != null) 'maxAgeYears': maxAgeYears,
        if (videoSource != null) 'video': videoSource!.toJson(),
        if (alsoStages.isNotEmpty) 'alsoStages': alsoStages,
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
        cities: [
          for (final c in (j['cities'] is List ? j['cities'] as List : const []))
            if ('$c'.trim().isNotEmpty) '$c'.trim(),
        ],
        minAgeYears: (j['minAgeYears'] as num?)?.toInt(),
        maxAgeYears: (j['maxAgeYears'] as num?)?.toInt(),
        videoSource: VideoSource.fromJson(j['video']),
        alsoStages: [
          for (final s in (j['alsoStages'] is List ? j['alsoStages'] as List : const []))
            if ('$s'.trim().isNotEmpty) '$s'.trim(),
        ],
      );
}

/// Every stage [item] should appear under: where it is filed, plus any stage
/// it declares in [ContentItem.alsoStages].
///
/// Unknown or malformed keys are dropped rather than guessed at, matching what
/// [TimelineStage.fromKey] does with the map's own keys — a typo in the CMS
/// must not invent a stage.
Set<String> stagesForItem(ContentItem item, String homeStage) => {
      homeStage,
      for (final s in item.alsoStages)
        if (TimelineStage.fromKey(s) != null) s,
    };

/// The stage keys from [from] to [to] inclusive, for authoring a range.
///
/// Returns empty if the two are different kinds or the order is reversed,
/// rather than producing something surprising: "weeks 20 to month 4" is a
/// mistake, and silently returning 40 weeks would hide it.
List<String> stageRange(String from, String to) {
  final a = TimelineStage.fromKey(from);
  final b = TimelineStage.fromKey(to);
  if (a == null || b == null || a.kind != b.kind || b.index < a.index) return const [];
  return [
    for (var i = a.index; i <= b.index; i++)
      (a.kind == TimelineKind.pregnancyWeek
              ? TimelineStage.pregnancyWeek(i)
              : TimelineStage.childMonth(i))
          .key,
  ];
}

/// Everything published, indexed by stage key.
class ContentCatalog {
  /// Items as AUTHORED: each filed under its home stage exactly once.
  ///
  /// Reads should go through [itemsFor], which also returns items shared into
  /// a stage from elsewhere. This map stays the authored form so that saving a
  /// stage in the CMS writes back what was written, not an expanded copy —
  /// which is what made a shared item editable in one place.
  final Map<String, List<ContentItem>> byStage;
  const ContentCatalog(this.byStage);

  static const empty = ContentCatalog({});

  /// Everything shown at [stage]: filed here, plus shared in from other stages.
  ///
  /// Deduplicated by id, home stage first. An item that names its own home
  /// stage in alsoStages would otherwise appear twice, and the person who
  /// selected a range covering the item's own week has done nothing wrong.
  List<ContentItem> itemsFor(TimelineStage stage) {
    final home = byStage[stage.key] ?? const <ContentItem>[];
    final seen = {for (final i in home) i.id};
    final shared = <ContentItem>[];
    for (final entry in byStage.entries) {
      if (entry.key == stage.key) continue;
      for (final item in entry.value) {
        if (item.alsoStages.contains(stage.key) && seen.add(item.id)) {
          shared.add(item);
        }
      }
    }
    if (shared.isEmpty) return home;
    return [...home, ...shared];
  }

  /// Where [itemId] is authored, or null if nothing owns it.
  ///
  /// The CMS needs this to send an editor to the one copy that exists rather
  /// than letting them edit an appearance.
  String? homeStageOf(String itemId) {
    for (final entry in byStage.entries) {
      for (final item in entry.value) {
        if (item.id == itemId) return entry.key;
      }
    }
    return null;
  }
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
  /// Parse a catalogue, discarding only what cannot be read.
  ///
  /// [onBadItem] is called for each item that had to be dropped, so the caller
  /// can say so rather than let it pass unremarked.
  ///
  /// An item that throws used to take the WHOLE catalogue with it: one product
  /// whose price arrived as "990000" instead of 990000 — a serialization slip,
  /// a hand-edited row — and ContentItem.fromJson's cast threw, the parse
  /// returned null, and the app fell back to the catalogue bundled with the
  /// build. Every one of the 364 published items replaced by whatever shipped,
  /// silently, because of one field.
  ///
  /// The item is skipped instead. That matches how the stage keys and non-list
  /// values above are already treated, and it fails in proportion: one card
  /// missing rather than the whole timeline reverting.
  factory ContentCatalog.fromJson(
    Map<String, dynamic> j, {
    void Function(String stage, Object error)? onBadItem,
  }) {
    final out = <String, List<ContentItem>>{};
    for (final e in j.entries) {
      if (TimelineStage.fromKey(e.key) == null) continue;
      final list = e.value;
      if (list is! List) continue;
      final items = <ContentItem>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        try {
          items.add(ContentItem.fromJson(raw.cast<String, dynamic>()));
        } catch (err) {
          // Deliberately not coerced: a price read wrongly is worse than a
          // product that does not appear.
          onBadItem?.call(e.key, err);
        }
      }
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

/// The reason to open this card THIS week rather than any week.
///
/// A shelf of lessons and products is forgettable; what makes it worth a look
/// is that it is specific to right now. Everything here is true by
/// construction — how far along you are, how much is left, what is coming next
/// — rather than manufactured urgency, which has no place in a pregnancy app.
class TimelineHighlight {
  /// 0..1 through the journey being tracked (40 weeks, or 60 months).
  final double progress;

  /// How many weeks/months remain. Null once the journey has no fixed end.
  final int? remaining;

  /// True at the halfway point, worth marking.
  final bool isHalfway;

  /// The next stage, so the card can say what is coming.
  final TimelineStage? next;

  const TimelineHighlight({
    required this.progress,
    required this.remaining,
    required this.isHalfway,
    required this.next,
  });
}

TimelineHighlight highlightFor(TimelineStage stage) {
  switch (stage.kind) {
    case TimelineKind.pregnancyWeek:
      final remaining = maxPregnancyWeek - stage.index;
      return TimelineHighlight(
        progress: stage.index / maxPregnancyWeek,
        remaining: remaining,
        // Week 20 of 40 — the midpoint people actually mark.
        isHalfway: stage.index == maxPregnancyWeek ~/ 2,
        next: stage.index < maxPregnancyWeek
            ? TimelineStage.pregnancyWeek(stage.index + 1)
            : null,
      );
    case TimelineKind.childMonth:
      return TimelineHighlight(
        progress: stage.index / maxChildMonth,
        // Childhood doesn't "end", so a countdown would be meaningless.
        remaining: null,
        isHalfway: false,
        next: stage.index < maxChildMonth
            ? TimelineStage.childMonth(stage.index + 1)
            : null,
      );
  }
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

/// Who is looking at the shelf. Both fields are optional because both are
/// optional in the profile — a woman who skipped them still gets a full shelf,
/// she just doesn't get the targeted extras.
class ContentViewer {
  final String city;
  final int? ageYears;

  const ContentViewer({this.city = '', this.ageYears});

  static const anonymous = ContentViewer();
}

/// City spellings that mean the same place.
///
/// The profile takes a free-text city in an app used in three languages, so
/// "Алматы", "Almaty" and "Алма-Ата" all arrive. Without this, targeting would
/// silently fail for anyone who typed the Latin form — the shelf would look
/// normal, so nobody would ever notice.
///
/// This covers the cities the product actually operates in. Anything else falls
/// through as itself: an unrecognised spelling matches only an identical one,
/// which is a miss rather than a wrong hit.
const _cityAliases = <String, String>{
  'almaty': 'алматы',
  'алма-ата': 'алматы',
  'alma-ata': 'алматы',
  'astana': 'астана',
  'nur-sultan': 'астана',
  'нур-султан': 'астана',
  'нұр-сұлтан': 'астана',
  'shymkent': 'шымкент',
  'чимкент': 'шымкент',
  'karaganda': 'караганда',
  'qaraghandy': 'караганда',
  'қарағанды': 'караганда',
  'aktobe': 'актобе',
  'ақтөбе': 'актобе',
  'atyrau': 'атырау',
  'атырау': 'атырау',
  'taraz': 'тараз',
  'pavlodar': 'павлодар',
  'oskemen': 'усть-каменогорск',
  'өскемен': 'усть-каменогорск',
  'semey': 'семей',
  'kostanay': 'костанай',
  'қостанай': 'костанай',
  'kyzylorda': 'кызылорда',
  'қызылорда': 'кызылорда',
  'oral': 'уральск',
  'орал': 'уральск',
  'aktau': 'актау',
  'ақтау': 'актау',
  'turkestan': 'туркестан',
  'түркістан': 'туркестан',
  'taldykorgan': 'талдыкорган',
  'талдықорған': 'талдыкорган',
};

/// Reduce a written city to something comparable: case, surrounding space and
/// the ё/е split, then the alias table.
String normalizeCity(String raw) {
  final trimmed = raw.trim().toLowerCase().replaceAll('ё', 'е');
  if (trimmed.isEmpty) return '';
  return _cityAliases[trimmed] ?? trimmed;
}

/// Whether [item] should be shown to [viewer].
///
/// An item with no constraints is for everyone, always — that is the overwhelming
/// majority and it never depends on the profile. A constraint the profile cannot
/// satisfy excludes the item, and that deliberately includes the case where the
/// profile simply doesn't say: without a city we cannot claim an Almaty-only
/// product is relevant, and quietly showing it anyway would be a promise the
/// delivery can't keep.
bool suitsViewer(ContentItem item, ContentViewer viewer) {
  if (item.isForEveryone) return true;

  if (item.cities.isNotEmpty) {
    final want = normalizeCity(viewer.city);
    if (want.isEmpty) return false;
    if (!item.cities.map(normalizeCity).contains(want)) return false;
  }

  final min = item.minAgeYears;
  final max = item.maxAgeYears;
  if (min != null || max != null) {
    final age = viewer.ageYears;
    if (age == null) return false;
    if (min != null && age < min) return false;
    if (max != null && age > max) return false;
  }

  return true;
}

/// The items from [all] that suit [viewer], in the order they were authored.
///
/// Never returns fewer than the unconstrained items, so a sparsely-filled
/// profile can only cost someone the extras — never the baseline shelf.
List<ContentItem> itemsForViewer(List<ContentItem> all, ContentViewer viewer) =>
    [for (final i in all) if (suitsViewer(i, viewer)) i];

/// Where a lesson's video actually lives.
///
/// WHY THIS IS NOT JUST A URL
///
/// The lessons are meant to feel like Umay's, not like someone else's platform
/// — a player we control, with our branding and no third party's. That is a
/// hosting decision, and it should not be a code decision: the catalogue is
/// authored as data and imported in bulk, so moving from one host to another
/// has to be a re-import, not a rewrite.
///
/// A NOTE ON YOUTUBE, recorded so nobody has to rediscover it. Unlisted YouTube
/// links are a reasonable way to author content early, but YouTube's terms
/// require playback through their player with its branding intact, and forbid
/// extracting the underlying stream. Hiding the logo or feeding the stream to
/// our own player is not a grey area, and the penalty lands on the whole
/// channel at once — every lesson, mid-course, for every user.
///
/// So [VideoProvider.youtube] is deliberately NOT playable in-app: it opens
/// externally, which is compliant. Direct HLS or MP4 from a host that sells
/// white-labelling (Bunny Stream, Cloudflare Stream, Mux, Vimeo Business) plays
/// inline in our own player. Both are expressible here, so the catalogue can be
/// authored today and moved later without touching this file.
enum VideoProvider {
  /// HLS manifest (.m3u8) — what every white-label host serves.
  hls,

  /// A plain progressive file. Simple, and fine for short lessons.
  mp4,

  /// Opens in the YouTube app or browser. Never played inline: see above.
  youtube,
}

class VideoSource {
  final VideoProvider provider;

  /// The manifest/file URL, or the YouTube watch URL.
  final String url;

  /// Optional still shown before playback starts.
  final String posterUrl;

  const VideoSource({
    required this.provider,
    required this.url,
    this.posterUrl = '',
  });

  /// Whether this can play inside our own player.
  ///
  /// The single place that decision is made, so a new provider cannot
  /// accidentally become inline-playable by being added to the enum.
  bool get playsInline =>
      (provider == VideoProvider.hls || provider == VideoProvider.mp4) && url.trim().isNotEmpty;

  bool get isEmpty => url.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'url': url,
        if (posterUrl.isNotEmpty) 'posterUrl': posterUrl,
      };

  /// Parse a source, tolerating the shapes a catalogue actually arrives in.
  ///
  /// Returns null for anything unusable rather than a half-built source, so a
  /// lesson with a broken entry shows as "coming soon" instead of a dead
  /// player. An unrecognised provider falls back to [VideoProvider.youtube] —
  /// the one that opens externally — because guessing that an unknown URL is
  /// safe to stream inline is the wrong way to be wrong.
  static VideoSource? fromJson(Object? j) {
    if (j is String) return j.trim().isEmpty ? null : VideoSource(provider: guessProvider(j), url: j.trim());
    if (j is! Map) return null;
    final url = '${j['url'] ?? ''}'.trim();
    if (url.isEmpty) return null;
    final raw = '${j['provider'] ?? ''}'.toLowerCase();
    final provider = VideoProvider.values.where((p) => p.name == raw).firstOrNull ?? guessProvider(url);
    return VideoSource(
      provider: provider,
      url: url,
      posterUrl: '${j['posterUrl'] ?? ''}'.trim(),
    );
  }

  /// Infer a provider from a bare URL, for a catalogue authored before the
  /// field existed.
  static VideoProvider guessProvider(String url) {
    final u = url.toLowerCase();
    if (u.contains('youtube.com') || u.contains('youtu.be')) return VideoProvider.youtube;
    if (u.contains('.m3u8')) return VideoProvider.hls;
    if (u.endsWith('.mp4') || u.contains('.mp4?')) return VideoProvider.mp4;
    // Unknown: treat as external. Streaming something we cannot identify into
    // our own player is the riskier assumption.
    return VideoProvider.youtube;
  }
}
