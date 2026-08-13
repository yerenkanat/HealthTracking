/// Screen 27 — «Гиды».
///
/// WHY THIS EXISTS
///
/// 364 items across roughly 101 stages are downloaded to every phone by
/// `GET /content`. Exactly ONE stage was ever rendered — this week's shelf on
/// the Today tab — so the rest was carried around and shown nowhere. And a
/// woman with neither a due date nor a child had no stage at all, which meant
/// she could reach no published material whatsoever: the app had a library and
/// no door into it.
///
/// This is the door. Search across everything, four topic shelves, and — when
/// the app does know where she is — her own stage, offered rather than imposed.
///
/// WHAT IT DELIBERATELY DOES NOT SAY
///
/// The spec draws this last section as «Читают в 7 месяцев». Nothing in this
/// app measures who reads what: `net/telemetry_batcher.dart` carries vitals and
/// location and nothing else, and there is no content-view event anywhere in
/// the codebase. A readership number here would be invented, which is the same
/// manufactured social proof `timeline_content_card.dart` refuses by name. The
/// section is titled for her stage instead — «Для 7 месяцев» — which is true,
/// and is the actual reason the material is worth her time.
///
/// The search, the dedupe and the topic rules are pure functions in
/// `domain/timeline_content.dart`, unit-tested there.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/emergency_help_repository.dart';
import '../../domain/emergency_help.dart';
import '../../domain/timeline_content.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../calendar/labour_signs_screen.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../emergency/emergency_help_screen.dart';
import '../theme.dart';
import '../widgets/fitted_title.dart';
import '../widgets/glass.dart';
import 'timeline_content_screen.dart';

/// The label for a shelf. Public so the tests and the tiles agree on one name.
String topicLabel(L10n l, ContentTopic topic) => switch (topic) {
      ContentTopic.pregnancy => l.t('gd_topic_pregnancy'),
      ContentTopic.baby => l.t('gd_topic_baby'),
      ContentTopic.child => l.t('gd_topic_child'),
      ContentTopic.mother => l.t('gd_topic_mother'),
    };

IconData _topicIcon(ContentTopic topic) => switch (topic) {
      ContentTopic.pregnancy => Icons.pregnant_woman_rounded,
      ContentTopic.baby => Icons.child_friendly_rounded,
      ContentTopic.child => Icons.child_care_rounded,
      ContentTopic.mother => Icons.favorite_rounded,
    };

Color _topicColor(ContentTopic topic) => switch (topic) {
      ContentTopic.pregnancy => Ds.pastelPink,
      ContentTopic.baby => Ds.pastelButter,
      ContentTopic.child => Ds.pastelMint,
      ContentTopic.mother => Ds.pastelLilac,
    };

class GuidesScreen extends StatefulWidget {
  /// The whole published catalogue.
  ///
  /// Pass the value of the ContentStore notifier, not a snapshot taken at
  /// launch: a stage published in the back office this morning is in the
  /// catalogue by the time she opens this screen, and reading a captured copy
  /// would show her yesterday's library until the next cold start.
  final ContentCatalog catalog;

  /// Where she is, when the app knows. Null is a supported state and the
  /// reason this screen exists — the stage section is simply absent.
  final TimelineStage? stage;

  /// Narrows to what can actually be delivered to her, the same rule the
  /// weekly shelf applies. A city-limited product must not be offered here
  /// just because a different screen is showing it.
  final ContentViewer viewer;

  /// Whether she is expecting — decides which scenarios screen 37 shows her
  /// and whether it carries the link to «Признаки родов».
  final bool pregnant;

  final void Function(ContentItem item)? onOpen;

  /// Place the 103 call. Injected so a widget test can drive the amber card's
  /// screen without a dialler; production leaves it null.
  final Future<bool> Function(String tel)? onCall;

  /// Screen 37's three profile facts: where an ambulance is sent, her city as
  /// the fallback line on that card, and her own doctor's number.
  ///
  /// Passed down rather than read from a controller so this screen stays a
  /// pure widget — and so the emergency screen it opens shows the address a
  /// dispatcher would need instead of nothing.
  final String address;
  final String city;
  final String doctorPhone;

  /// Open the profile editor, for «Добавьте адрес» and the missing doctor's
  /// number. Null leaves both as plain instructions rather than dead buttons.
  final VoidCallback? onEditProfile;

  const GuidesScreen({
    super.key,
    required this.catalog,
    this.stage,
    this.viewer = ContentViewer.anonymous,
    this.pregnant = false,
    this.onOpen,
    this.onCall,
    this.address = '',
    this.city = '',
    this.doctorPhone = '',
    this.onEditProfile,
  });

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

/// What screen 37 reads off the profile, as one comparable value.
///
/// A record, so equality is structural: republishing an identical profile does
/// not rebuild the open emergency screen.
typedef _Screen37Inputs = ({
  String address,
  String city,
  String doctorPhone,
  bool pregnant,
});

class _GuidesScreenState extends State<GuidesScreen> {
  final _search = TextEditingController();

  /// Screen 37's inputs, re-published to a route that is ALREADY open.
  ///
  /// MaterialPageRoute builds its page once and keeps it. A route built
  /// directly from `widget.address` therefore freezes whatever the profile said
  /// at the instant of the tap: she taps «Добавьте адрес», types her address,
  /// saves — and the card still says «Добавьте адрес», with no way to see the
  /// truth short of popping back to Гиды and opening the card again. That is
  /// this repo's «assumes the request succeeded» family, on the screen where it
  /// costs the most.
  ///
  /// So the values cross the route boundary through a notifier instead:
  /// [didUpdateWidget] republishes them when the shell rebuilds this screen,
  /// and the ValueListenableBuilder inside the route paints them.
  late final ValueNotifier<_Screen37Inputs> _screen37 =
      ValueNotifier(_inputsFrom(widget));

  static _Screen37Inputs _inputsFrom(GuidesScreen w) => (
        address: w.address,
        city: w.city,
        doctorPhone: w.doctorPhone,
        pregnant: w.pregnant,
      );

  @override
  void didUpdateWidget(covariant GuidesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _inputsFrom(widget);
    if (next == _screen37.value) return;
    // Published AFTER this frame, never inside it. The listener lives in a
    // PUSHED route — a separate element tree — and marking it dirty while the
    // shell is building this one is «setState() called during build», which
    // costs the rebuild that this whole mechanism exists to deliver.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _screen37.value = next;
    });
  }

  /// How many of her own stage's items the section shows before deferring to
  /// the stage screen. Three, like the dashboard card, so the two read as the
  /// same shelf seen from two places.
  static const _stagePreview = 3;

  @override
  void dispose() {
    _search.dispose();
    _screen37.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final locale = l.locale.name;
    final guides = allGuides(widget.catalog, viewer: widget.viewer);
    final query = _search.text.trim();
    final searching = query.isNotEmpty;
    final results = searching ? searchGuides(guides, query, locale) : const <GuideEntry>[];

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: FittedTitle(l.t('gd_title'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _SearchField(
              controller: _search,
              hint: l.t('gd_search'),
              clearLabel: l.t('gd_search_clear'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            if (searching)
              ..._results(l, locale, results)
            else ...[
              // First, before any browsing: the one thing on this screen that
              // is time-critical. Everything below it can wait; this cannot.
              _RedFlagCard(
                onTap: () => _openRedFlags(context),
              ),
              const SizedBox(height: 18),
              if (guides.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(l.t('gd_empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Palette.textDim, height: 1.4)),
                )
              else ...[
                _SectionHeader(l.t('gd_topics')),
                _TopicGrid(
                  counts: guideTopicCounts(guides),
                  onOpen: (topic) => _openTopic(context, topic, guides),
                ),
              ],
              ..._stageSection(l, guides),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _results(L10n l, String locale, List<GuideEntry> results) {
    if (results.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(l.t('gd_nothing_found'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.textDim, height: 1.4)),
        ),
      ];
    }
    return [
      _SectionHeader(l.t('gd_results', {'n': results.length})),
      for (final g in results)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ContentTile(item: g.item, onOpen: widget.onOpen),
        ),
    ];
  }

  /// «Для 7 месяцев» — her own stage, when there is one.
  ///
  /// Absent rather than empty when the app does not know where she is. An
  /// invitation to add a due date belongs on the Today card, which already
  /// carries one; repeating it here would make the guides library look like it
  /// needs a due date to work, and it does not.
  List<Widget> _stageSection(L10n l, List<GuideEntry> guides) {
    final stage = widget.stage;
    if (stage == null) return const [];
    final items = itemsForViewer(widget.catalog.itemsFor(stage), widget.viewer);
    if (items.isEmpty) return const [];
    final preview = items.take(_stagePreview).toList();
    return [
      const SizedBox(height: 18),
      _SectionHeader(l.t('gd_for_stage', {'stage': stageLabel(l, stage)})),
      for (final item in preview)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ContentTile(item: item, onOpen: widget.onOpen),
        ),
      if (items.length > preview.length)
        SizedBox(
          height: 48,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TimelineContentScreen(
                stage: stage,
                items: items,
                onOpen: widget.onOpen,
              ),
            )),
            child: Text(l.t('tl_see_all'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Palette.violet)),
          ),
        ),
    ];
  }

  void _openTopic(BuildContext context, ContentTopic topic, List<GuideEntry> guides) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _TopicScreen(
        topic: topic,
        guides: guidesForTopic(guides, topic),
        onOpen: widget.onOpen,
      ),
    ));
  }

  /// Screen 37 «Экстренная помощь» — for everybody, tailored to who is reading.
  ///
  /// It used to fork: expecting → LabourSignsScreen, everybody else → screen 37.
  /// That fork was the reason three of the nine shipped scenarios —
  /// «кровотечение», «преэклампсия», «малыш перестал шевелиться» — could not be
  /// opened by the only readers they are written for, while LabourSignsScreen
  /// (which has no navigation of its own) was a dead end with no ambulance
  /// card, no dispatcher address and no doctor's number on it. So the card
  /// opens screen 37 for her too, with the labour reference linked FROM it.
  ///
  /// Screen 37 itself used to be the TRIAGE screen for non-pregnant readers —
  /// one paragraph of red flags, one 103 button, and a confirm-to-leave gate
  /// designed for an alert that latched by itself. It was the wrong screen
  /// twice over: nothing had latched, so the gate was ceremony; and a reference
  /// card tapped on purpose needs the scenarios, the address a dispatcher asks
  /// for and her own doctor's number, none of which triage carries.
  void _openRedFlags(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FutureBuilder<EmergencyHelp>(
        future: loadEmergencyHelp(),
        // The screen is NEVER blank while the list loads. `EmergencyHelp.empty`
        // still draws the 103 card, the address and the doctor — the half that
        // matters most — and the scenarios appear a frame later. A spinner here
        // would be a spinner on the screen somebody opened because a child
        // cannot breathe.
        initialData: EmergencyHelp.empty,
        builder: (_, snap) => ValueListenableBuilder<_Screen37Inputs>(
          // Not `widget.address` — see [_screen37]. An address saved from the
          // prompt ON that screen has to appear ON that screen.
          valueListenable: _screen37,
          builder: (routeContext, p, __) => EmergencyHelpScreen(
            help: snap.data ?? EmergencyHelp.empty,
            address: p.address,
            city: p.city,
            doctorPhone: p.doctorPhone,
            pregnant: p.pregnant,
            onLabourSigns: p.pregnant
                ? () => Navigator.of(routeContext).push(
                      MaterialPageRoute(builder: (_) => const LabourSignsScreen()),
                    )
                : null,
            onEditProfile: widget.onEditProfile,
            onCall: (tel) async =>
                widget.onCall?.call(tel) ?? launchUrl(Uri(scheme: 'tel', path: tel)),
          ),
        ),
      ),
    ));
  }
}

/// One topic's whole shelf.
class _TopicScreen extends StatelessWidget {
  final ContentTopic topic;
  final List<GuideEntry> guides;
  final void Function(ContentItem item)? onOpen;
  const _TopicScreen({required this.topic, required this.guides, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: FittedTitle(topicLabel(l, topic))),
        body: guides.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(l.t('tl_none_for_stage'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Palette.textDim, height: 1.4)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  for (final g in guides)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ContentTile(item: g.item, onOpen: onOpen),
                    ),
                ],
              ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String clearLabel;
  final ValueChanged<String> onChanged;
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.clearLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          // The label doubles as the accessible name; a bare magnifier is not
          // one, and this is the first control on the screen.
          labelText: hint,
          prefixIcon: const Icon(Icons.search_rounded, color: Palette.textDim),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: clearLabel,
                  icon: const Icon(Icons.close_rounded, color: Palette.textDim),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DsShape.radiusInput),
            borderSide: const BorderSide(color: Ds.hairline, width: DsShape.borderWidth),
          ),
        ),
      );
}

/// «Когда сразу звонить 103».
///
/// Amber, not the emergency red: red is reserved for SOS and for the screen
/// that appears when something IS happening. This is a reference card somebody
/// may be reading calmly, and making the two look identical makes neither mean
/// anything (see widgets/call_ambulance.dart, same rule).
class _RedFlagCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RedFlagCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return DsCard(
      color: Ds.pastelButter,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 22, color: Ds.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.t('gd_call_title'),
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Ds.amberText)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The signs are ON the card, not behind the tap. Somebody scrolling
          // at 2am has to be able to recognise herself without opening
          // anything first.
          Text(l.t('gd_call_body'),
              style: const TextStyle(
                  color: Ds.textBody, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(l.t('gd_call_open'),
                  style: const TextStyle(
                      color: Ds.amberText,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const Icon(Icons.chevron_right_rounded, size: 20, color: Ds.amberText),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 2x2 of shelves.
///
/// Every topic is drawn even at zero. A tile that disappears when its shelf
/// empties reads as a bug and hides the fact that nobody has filed anything
/// under «Мама» yet — which is a thing worth knowing, not worth hiding.
class _TopicGrid extends StatelessWidget {
  final Map<ContentTopic, int> counts;
  final void Function(ContentTopic topic) onOpen;
  const _TopicGrid({required this.counts, required this.onOpen});

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Wide enough that two lines of Kazakh («Бір жасқа дейін») and the
        // count both fit without the tile clipping.
        childAspectRatio: 1.45,
        children: [
          for (final topic in ContentTopic.values)
            _TopicTile(
              topic: topic,
              count: counts[topic] ?? 0,
              onTap: () => onOpen(topic),
            ),
        ],
      );
}

class _TopicTile extends StatelessWidget {
  final ContentTopic topic;
  final int count;
  final VoidCallback onTap;
  const _TopicTile({required this.topic, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final label = topicLabel(l, topic);
    final sub = count == 0 ? l.t('gd_topic_empty') : l.t('gd_topic_count', {'n': count});
    return Semantics(
      button: true,
      label: '$label. $sub',
      child: DsCard(
        color: _topicColor(topic),
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(_topicIcon(topic), size: 24, color: Ds.ink),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Palette.text)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Palette.textDim)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
              color: Palette.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            )),
      );
}
