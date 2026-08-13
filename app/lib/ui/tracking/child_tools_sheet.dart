/// Screen 15a — «экран „Ребёнок“ со списком инструментов».
///
/// The «Ребёнок» tab is a full-bleed map with four unlabelled controls floating
/// over it, and one of them — a folder glyph — was the only route to the child's
/// card. Under that card hang Медкарта, Прививки, Рост и вес, Развитие, Дневник
/// малыша, Детектор плача, Прикорм, Безопасность дома and Болезни: nine screens,
/// all three taps deep, none of them named anywhere on the tab they belong to.
///
/// This is the list the spec asks for. The map stays — it is the right default
/// for that tab — and the tools sit beside it under a LABELLED control, so every
/// care screen is two taps from the tab bar.
///
/// The rows only ever offer what can actually work. Five of the nine are keyed
/// on the child's age, so without a date of birth they would be dead ends; in
/// their place the sheet says so and offers the editor that fixes it.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/family.dart';
import '../../l10n/l10n_scope.dart';
import '../ds_widgets.dart';
import '../theme.dart';
import 'child_care_routes.dart';
import 'family_sheets.dart';

/// The nine care screens, plus the one repair action the sheet can offer.
enum ChildTool {
  medicalId,
  illness,
  development,
  vaccinations,
  growth,
  newbornLog,
  cry,
  solids,
  homeSafety,

  /// Not a tool: «Укажите дату рождения», which is what unlocks the five rows
  /// that are keyed on age. Shown instead of them, never beside them.
  setBirthDate,
}

/// Title key, icon, and whether the screen behind it needs a date of birth.
const _tools = <(ChildTool, String, IconData, bool)>[
  (ChildTool.medicalId, 'ei_title', Icons.medical_information_outlined, false),
  (ChildTool.vaccinations, 'vac_title', Icons.vaccines_outlined, true),
  (ChildTool.growth, 'grw_title', Icons.monitor_weight_outlined, false),
  (ChildTool.development, 'dev_title', Icons.timeline_rounded, true),
  (ChildTool.newbornLog, 'nb_title', Icons.child_friendly_outlined, false),
  (ChildTool.cry, 'cry_title', Icons.graphic_eq_rounded, false),
  (ChildTool.solids, 'sol_card_title', Icons.restaurant_outlined, true),
  (ChildTool.homeSafety, 'hs_card_title', Icons.shield_outlined, true),
  (ChildTool.illness, 'ill_title', Icons.sick_outlined, true),
];

/// Open the tools list for [childId] and act on what she picks.
///
/// The sheet RETURNS the choice rather than pushing from inside itself: a route
/// pushed from a modal's own context goes on top of a sheet that is closing,
/// and the screen then appears behind a barrier that is fading out.
Future<void> showChildToolsSheet(
  BuildContext context,
  AppController c, {
  required String childId,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  ChildProfile? found;
  for (final ch in c.children) {
    if (ch.id == childId) found = ch;
  }
  final child = found;
  if (child == null) return;

  final picked = await showModalBottomSheet<ChildTool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _ChildToolsSheet(
      childName: child.name,
      hasDateOfBirth: child.hasDateOfBirth,
      // The cry classifier is reached through the authenticated backend proxy,
      // so signed out the row would open a screen that can only fail.
      signedIn: c.isSignedIn,
    ),
  );
  if (picked == null || !context.mounted) return;

  switch (picked) {
    case ChildTool.medicalId:
      openMedicalId(context, c, child);
    case ChildTool.illness:
      openIllness(context, child, at);
    case ChildTool.development:
      openDevelopment(context, child, at);
    case ChildTool.vaccinations:
      openVaccinations(context, c, child, at);
    case ChildTool.growth:
      openGrowth(context, c, child);
    case ChildTool.newbornLog:
      openNewbornLog(context, c, child, at);
    case ChildTool.cry:
      openCryInsight(context, c);
    case ChildTool.solids:
      openSolids(context, child, at);
    case ChildTool.homeSafety:
      openHomeSafety(context, c, child, at);
    case ChildTool.setBirthDate:
      await showEditChildSheet(context, c, child);
  }
}

class _ChildToolsSheet extends StatelessWidget {
  final String childName;
  final bool hasDateOfBirth;
  final bool signedIn;
  const _ChildToolsSheet({
    required this.childName,
    required this.hasDateOfBirth,
    required this.signedIn,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final rows = <DsRow>[
      for (final (tool, key, icon, needsDob) in _tools)
        if ((!needsDob || hasDateOfBirth) && (tool != ChildTool.cry || signedIn))
          DsRow(
            leading: Icon(icon, size: 22, color: Palette.violet),
            label: l.t(key),
            onTap: () => Navigator.of(context).pop(tool),
          ),
      // Five of the nine are keyed on age. Rather than hide them silently —
      // which is what the child's card does, and why a parent who skipped the
      // birthday never learns прививки exist — say what is missing and offer
      // the editor that fills it in.
      if (!hasDateOfBirth)
        DsRow(
          leading: const Icon(Icons.cake_outlined, size: 22, color: Palette.amber),
          label: l.t('child_no_dob'),
          subtitle: l.t('tools_needs_dob'),
          onTap: () => Navigator.of(context).pop(ChildTool.setBirthDate),
        ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: Palette.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(l.t('tr_tools'),
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(childName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Palette.textDim, fontSize: 13.5)),
            ),
            // Nine rows do not fit a 320dp phone with the font slider up, so
            // the list SCROLLS inside the sheet rather than the sheet growing
            // past the screen. No height constraint on the card itself — one
            // here bounds the column inside it and the last row is cut off
            // instead of scrolled to.
            Flexible(
              child: SingleChildScrollView(child: DsListCard(rows: rows)),
            ),
          ],
        ),
      ),
    );
  }
}
