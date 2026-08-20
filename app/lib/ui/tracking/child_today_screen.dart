/// Frame 15a — «Ребёнок · Сегодня», the second half of the child hub.
///
/// This replaces `child_tools_sheet.dart`: nine flat rows in a modal, behind a
/// floating control on the map, with no counts on any of them. The spec
/// (`docs/CLAUDE-app-design.md`, § «15a · Ребёнок · Сегодня») asks for a
/// grouped list with a subline under each of the four daily tiles, and for the
/// whole thing to be a SEGMENT of the tab rather than a sheet over it.
///
/// ## Every subline is a reading or it is absent
///
/// The four sublines come from [ChildTodayCounts], which reads the controller
/// and nothing else. There is no default, no placeholder and no rounded-up
/// figure anywhere below:
///
///   * «Почему плачет» — the last analysis, its reason and its date, and the
///     reason is withheld below the served confidence threshold exactly as the
///     screen behind it withholds it. No history at all says so in words.
///   * «Дневник малыша» — feeds + diapers + sleep stretches logged TODAY. Zero
///     is a real answer and prints as «Сегодня отмечено: 0».
///   * «Рост и вес» — the last measurement and its date. **No percentile.**
///     `domain/child_growth.dart:12-21` refuses WHO bands by a written
///     decision; the date is the freshness stamp instead.
///   * «Прививки» — `vaccinesToCatchUp` over the SERVED schedule, worded
///     «Стоит уточнить: N». Not «просрочена»: `domain/vaccination.dart:126`
///     names that state `passed` and says in as many words that the app has no
///     idea what the child has actually received.
///
/// ## No cry banner
///
/// The visual reference puts an invitation banner above this grid, whose first
/// tile is «Почему плачет». Two entries to one screen on one screen is the
/// duplicate-control defect `docs/UI_REVIEW_CHECKLIST.md` exists for. The tile
/// keeps the banner's content (the last check, with its date) and its
/// prominence (first position); the banner is dropped.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/cry_settings_repository.dart';
import '../../data/vaccination_schedule_repository.dart';
import '../../domain/child_growth.dart';
import '../../domain/cry_analysis.dart';
import '../../domain/family.dart';
import '../../domain/newborn_log.dart';
import '../../domain/solids_guide.dart';
import '../../domain/vaccination.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';

/// Everything the four daily tiles print, read off the controller in one place.
///
/// A value object rather than four getters on the widget, so a test can assert
/// that the numbers on screen MOVED when the controller's data moved — which is
/// the only way to tell a wired count from a literal that happens to match.
@immutable
class ChildTodayCounts {
  /// The most recent cry analysis, or null when there has never been one.
  final CryResult? lastCry;

  /// The served «may we name the reason» threshold, applied here too so the
  /// tile and the screen behind it cannot disagree about the same recording.
  final double cryThreshold;

  /// The classifier is reached through the authenticated proxy. Signed out the
  /// tile stays — it explains and leads to sign-in — rather than vanishing.
  final bool signedIn;

  /// Today's newborn log.
  final NewbornDaySummary loggedToday;

  /// The newest growth measurement, or null when none was ever recorded.
  final GrowthPoint? lastGrowth;

  /// How many scheduled vaccines are past their age and not recorded as done,
  /// or **null when the child has no date of birth** — with no age there is no
  /// schedule position, and a 0 there would be a claim, not a count.
  final int? vaccinesToCheck;

  const ChildTodayCounts({
    required this.lastCry,
    required this.cryThreshold,
    required this.signedIn,
    required this.loggedToday,
    required this.lastGrowth,
    required this.vaccinesToCheck,
  });

  /// Read the four tiles' figures for [child] as of [now].
  factory ChildTodayCounts.read(
      AppController c, ChildProfile child, DateTime now) {
    final growth = c.growthFor(child.id); // oldest-first
    return ChildTodayCounts(
      lastCry: c.cryHistory.isEmpty ? null : c.cryHistory.first,
      cryThreshold: cryMinConfidence(),
      signedIn: c.isSignedIn,
      loggedToday: summaryFor(c.newbornLogFor(child.id), now),
      lastGrowth: growth.isEmpty ? null : growth.last,
      // Over the SERVED schedule and the SERVED window, like the screen the
      // tile opens. Reading the compiled-in calendar here would have the tile
      // say «Стоит уточнить: 2» over a screen that lists one.
      vaccinesToCheck: child.hasDateOfBirth
          ? vaccinesToCatchUp(
                  child.ageInMonths(now),
                  c.vaccinesDoneFor(child.id),
                  servedVaccines(),
                  servedDueWindowMonths())
              .length
          : null,
    );
  }
}

/// `12.08.2026` — digits only.
///
/// Deliberately not a month name: the tile subline is already two items long at
/// 320 dp, and «12 тамыз 2026 ж.» does not fit beside a weight. Digits also
/// need no language, which is what the freshness stamp is for.
String childTileDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// «Почему плачет» — the last check, or why there is none to show.
String cryTileSubtitle(L10n l, ChildTodayCounts d) {
  // Signed out the analysis cannot run at all, so the tile says that instead of
  // reporting a history it would not be able to add to.
  if (!d.signedIn) return l.t('cry_signed_out');
  final last = d.lastCry;
  if (last == null) return l.t('child_tile_never');
  // The threshold applies HERE TOO. A tile printing «Голод» for a recording the
  // screen inside refuses to name would be the app disagreeing with itself,
  // with the confident claim made by the line read in passing.
  if (!last.namesReasonAt(d.cryThreshold)) {
    return '${l.t('cry_unsure_headline')} · ${childTileDate(last.at)}';
  }
  final code = CryReason.fromCode(last.reason) == null ? 'unknown' : last.reason;
  return '${l.t('cry_reason_$code')} · ${childTileDate(last.at)}';
}

/// «Дневник малыша» — everything logged today, feeds + diapers + sleep.
String newbornTileSubtitle(L10n l, ChildTodayCounts d) => l.t(
    'child_tile_logged',
    {
      'n': d.loggedToday.feeds +
          d.loggedToday.diapers +
          d.loggedToday.sleepStretches
    });

/// «Рост и вес» — the last measurement and its date. Never a percentile.
String growthTileSubtitle(L10n l, ChildTodayCounts d) {
  final p = d.lastGrowth;
  if (p == null) return l.t('child_tile_no_growth');
  return [
    if (p.weightKg != null) '${p.weightKg!.toStringAsFixed(1)} ${l.t('grw_kg')}',
    if (p.heightCm != null) '${p.heightCm!.toStringAsFixed(0)} ${l.t('grw_cm')}',
    childTileDate(p.at),
  ].join(' · ');
}

/// «Прививки» — how many are worth asking about. Never «просрочена».
String vaccinationTileSubtitle(L10n l, ChildTodayCounts d) {
  final n = d.vaccinesToCheck;
  if (n == null) return l.t('child_tile_set_dob');
  return n == 0 ? l.t('child_tile_vac_ok') : l.t('child_tile_vac_check', {'n': n});
}

/// The «Сегодня» pane. Body only — the segmented control above it belongs to
/// [ChildHubScreen], and the tab bar below it to the shell.
class ChildTodayView extends StatelessWidget {
  const ChildTodayView({
    super.key,
    required this.childName,
    required this.hasDateOfBirth,
    required this.ageMonths,
    required this.counts,
    required this.onOpenCry,
    required this.onOpenNewbornLog,
    required this.onOpenGrowth,
    required this.onOpenVaccinations,
    required this.onOpenMedicalId,
    required this.onOpenGuides,
    required this.onOpenDevelopment,
    required this.onOpenSolids,
    required this.onOpenHomeSafety,
    required this.onOpenIllness,
    required this.onSetBirthDate,
  });

  final String childName;
  final bool hasDateOfBirth;

  /// Null without a date of birth. Only used to decide whether weaning is the
  /// child's business yet.
  final int? ageMonths;

  final ChildTodayCounts counts;

  /// «Почему плачет». Signed out this leads to sign-in, not to a screen that
  /// could only fail — see [ChildTodayCounts.signedIn].
  final VoidCallback onOpenCry;
  final VoidCallback onOpenNewbornLog;
  final VoidCallback onOpenGrowth;
  final VoidCallback onOpenVaccinations;
  final VoidCallback onOpenMedicalId;
  final VoidCallback onOpenGuides;
  final VoidCallback onOpenDevelopment;
  final VoidCallback onOpenSolids;
  final VoidCallback onOpenHomeSafety;
  final VoidCallback onOpenIllness;

  /// The repair action for everything keyed on age.
  final VoidCallback onSetBirthDate;

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final months = ageMonths;
    return Material(
      color: Palette.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          // Whose screen this is. With two children the map segment has the
          // picker; this pane only has to name the answer it is showing.
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(childName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.ds.cardTitle),
          ),

          // ---- 1 · «Каждый день» — the 2×2 grid ----
          _SectionLabel(l.t('child_sec_daily')),
          _TileRow(children: [
            _DayTile(
              icon: Icons.graphic_eq_rounded,
              title: l.t('cry_title'),
              subtitle: cryTileSubtitle(l, counts),
              onTap: onOpenCry,
            ),
            _DayTile(
              icon: Icons.child_friendly_outlined,
              title: l.t('nb_title'),
              subtitle: newbornTileSubtitle(l, counts),
              onTap: onOpenNewbornLog,
            ),
          ]),
          const SizedBox(height: 12),
          _TileRow(children: [
            _DayTile(
              icon: Icons.monitor_weight_outlined,
              title: l.t('grw_title'),
              subtitle: growthTileSubtitle(l, counts),
              onTap: onOpenGrowth,
            ),
            _DayTile(
              icon: Icons.vaccines_outlined,
              title: l.t('vac_title'),
              subtitle: vaccinationTileSubtitle(l, counts),
              // Without a date of birth the schedule has no position for this
              // child, so the tile opens the editor that fixes that rather
              // than a calendar with nobody on it.
              onTap: hasDateOfBirth ? onOpenVaccinations : onSetBirthDate,
            ),
          ]),

          // ---- 2 · «На всякий случай» ----
          const SizedBox(height: 22),
          _SectionLabel(l.t('child_sec_justincase')),
          DsListCard(rows: [
            DsRow(
              leading: const Icon(Icons.medical_information_outlined,
                  size: 22, color: Palette.violet),
              label: l.t('ei_title'),
              onTap: onOpenMedicalId,
            ),
            DsRow(
              leading: const Icon(Icons.menu_book_outlined,
                  size: 22, color: Palette.violet),
              label: l.t('gd_title'),
              onTap: onOpenGuides,
            ),
          ]),

          // ---- 3 · the age-keyed tools ----
          //
          // Прививки is NOT repeated here even though it is keyed on age like
          // these are: it already has a tile above with a count on it, and the
          // tile self-explains without a birth date. Listing it twice on one
          // screen is the same duplicate-control defect the cry banner was
          // dropped for.
          const SizedBox(height: 22),
          _SectionLabel(l.t('tr_tools')),
          if (hasDateOfBirth)
            DsListCard(rows: [
              DsRow(
                leading: const Icon(Icons.timeline_rounded,
                    size: 22, color: Palette.violet),
                label: l.t('dev_title'),
                onTap: onOpenDevelopment,
              ),
              // Weaning, only across the window where it is the parent's
              // business — a solids guide is noise at three weeks.
              if (months != null && isSolidsWindow(months))
                DsRow(
                  leading: const Icon(Icons.restaurant_outlined,
                      size: 22, color: Palette.violet),
                  label: l.t('sol_card_title'),
                  onTap: onOpenSolids,
                ),
              DsRow(
                leading: const Icon(Icons.shield_outlined,
                    size: 22, color: Palette.violet),
                label: l.t('hs_card_title'),
                onTap: onOpenHomeSafety,
              ),
              DsRow(
                leading: const Icon(Icons.sick_outlined,
                    size: 22, color: Palette.violet),
                label: l.t('ill_title'),
                onTap: onOpenIllness,
              ),
            ])
          else
            // Said, rather than silently hidden — a parent who skipped the
            // birthday would otherwise never learn развитие and прикорм are in
            // the app at all. Carried over from the sheet this replaced.
            DsListCard(rows: [
              DsRow(
                leading: const Icon(Icons.cake_outlined,
                    size: 22, color: Palette.amber),
                label: l.t('child_no_dob'),
                subtitle: l.t('tools_needs_dob'),
                onTap: onSetBirthDate,
              ),
            ]),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 10),
        child: Text(text.toUpperCase(), style: context.ds.micro()),
      );
}

/// Two tiles of equal width and equal height.
///
/// [IntrinsicHeight] so the shorter subline does not leave a stub card beside a
/// two-line one — and so neither tile is given a fixed height that its Kazakh
/// subline would overflow at 130 % text.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 12),
            Expanded(child: children[1]),
          ],
        ),
      );
}

/// One tile of the «Каждый день» grid: glyph, title, and the line that carries
/// the number.
class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // One colour for all four. A tile whose glyph goes amber when there
          // is something to check would be grading `passed` as "missed", which
          // domain/vaccination.dart forbids in as many words.
          DsIconTile(icon: icon, color: Palette.violet, size: 38),
          const SizedBox(height: 10),
          Text(title, style: context.ds.rowLabel),
          const SizedBox(height: 4),
          // No maxLines: the subline is the reading, and a clipped reading is
          // worse than a tall card inside a ListView that scrolls anyway.
          Text(subtitle, style: context.ds.caption()),
        ],
      ),
    );
  }
}
