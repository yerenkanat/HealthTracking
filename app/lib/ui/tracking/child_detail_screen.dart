/// ChildDetailScreen — everything about one child in one place: age, tracker
/// battery, last check-in, last activity, their zones and how often each is
/// visited, and their alert history.
///
/// Deliberately read-only. The map, zones manager and alerts feed already own
/// those controls; this screen links out to them rather than growing a second
/// copy. Its one action is Edit, which opens the same sheet Settings used to.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/cry_analysis.dart';
import '../../domain/family.dart';
import '../../domain/geofence_alerts.dart';
import '../../domain/child_development.dart';
import '../../domain/vaccination.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';
import '../widgets/battery_colors.dart';
import '../../domain/child_growth.dart';
import '../../domain/newborn_log.dart';
import '../../domain/solids_guide.dart';
import '../../domain/home_safety.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'alerts_screen.dart';
import 'child_care_routes.dart';
import 'family_sheets.dart';
import '../ds_widgets.dart';
import 'zones_screen.dart';

class ChildDetailScreen extends StatelessWidget {
  final AppController controller;
  final String childId;
  final DateTime Function()? _nowFn;
  const ChildDetailScreen({
    super.key,
    required this.controller,
    required this.childId,
    DateTime Function()? now,
  }) : _nowFn = now;

  DateTime _now() => (_nowFn ?? DateTime.now)();

  ChildProfile? _child() {
    for (final c in controller.children) {
      if (c.id == childId) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final child = _child();
            // The child can be deleted from underneath us (e.g. from Settings).
            if (child == null) {
              return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(l.t('child_gone'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Palette.textDim, height: 1.4)),
                  ),
                ),
              );
            }

            final alerts = controller.alerts;
            // A battery belongs to a DEVICE.
            //
            // With no tracker linked, the last stored reading is about a
            // tracker that is not on this child, and this screen showed
            // «Заряд трекера 8%» for a family whose device list is empty. The
            // same contradiction was fixed on the tracking card; it lived here
            // too, one screen away, saying the opposite of what that one now
            // says.
            final hasTracker = controller.devices
                .any((d) => d.kind == DeviceKind.tag && d.childId == child.id);
            final battery = hasTracker ? controller.batteryFor(child.id) : null;
            final checkIn = lastCheckIn(alerts, child.name);
            final activity = lastActivityAt(alerts, child.name);
            final visits = zoneVisitCounts(alerts, child.name);
            final mine = filterAlertsByChild(alerts, child.name);
            final now = _now();

            String ago(DateTime at) {
              final d = now.difference(at);
              return l.ago(d.isNegative ? Duration.zero : d);
            }

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  title: Text(child.name),
                  actions: [
                    // Emergency medical-ID — one tap in the moment it matters.
                    IconButton(
                      icon: const Icon(Icons.medical_information_outlined),
                      tooltip: l.t('ei_title'),
                      onPressed: () =>
                          openMedicalId(context, controller, child),
                    ),
                    // Unwell-child guidance, always a tap away from the child's
                    // screen — fever and red flags, not buried.
                    IconButton(
                      icon: const Icon(Icons.sick_outlined),
                      tooltip: l.t('ill_title'),
                      onPressed: () => openIllness(context, child, now),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: l.t('set_edit_profile'),
                      onPressed: () =>
                          showEditChildSheet(context, controller, child),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                SliverList(
                  delegate: SliverChildListDelegate([
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Header(
                              child: child, now: now, controller: controller),
                          const SizedBox(height: 14),

                          // ---- Status ----
                          DsCard(
                            child: Column(
                              children: [
                                if (battery != null)
                                  _StatusRow(
                                    icon: Icons.battery_std_rounded,
                                    color: _batteryColor(battery),
                                    label: l.t('child_battery'),
                                    value: '$battery%',
                                  ),
                                if (checkIn != null) ...[
                                  if (battery != null) const _Divider(),
                                  _StatusRow(
                                    icon: Icons.how_to_reg_rounded,
                                    color: Palette.blue,
                                    label: l.t('child_last_checkin'),
                                    value: ago(checkIn),
                                  ),
                                ],
                                if (activity != null) ...[
                                  if (battery != null || checkIn != null)
                                    const _Divider(),
                                  _StatusRow(
                                    icon: Icons.history_rounded,
                                    color: Palette.violet,
                                    label: l.t('child_last_activity'),
                                    value: ago(activity),
                                  ),
                                ],
                                if (battery == null &&
                                    checkIn == null &&
                                    activity == null)
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: Text(l.t('child_no_activity'),
                                        style: const TextStyle(
                                            color: Palette.textDim,
                                            fontSize: 13)),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ---- Zones (links to the manager, which owns editing) ----
                          DsCard(
                            onTap: () =>
                                Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ZonesScreen(
                                  controller: controller, childId: child.id),
                            )),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text(l.t('child_zones').toUpperCase(),
                                      style: const TextStyle(
                                          color: Palette.textDim,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6)),
                                  const Spacer(),
                                  Text('${child.geofences.length}',
                                      style: const TextStyle(
                                          fontFamily: 'JetBrainsMono',
                                          fontWeight: FontWeight.w700,
                                          color: Palette.violet)),
                                  const Icon(Icons.chevron_right_rounded,
                                      size: 20, color: Palette.textDim),
                                ]),
                                if (visits.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  for (final v in visits.take(3))
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 3),
                                      child: Row(children: [
                                        const Icon(Icons.place_rounded,
                                            size: 15, color: Palette.good),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: Text(v.zone,
                                                style: const TextStyle(
                                                    fontSize: 14))),
                                        Text(
                                            l.t('zone_visits', {'n': v.visits}),
                                            style: const TextStyle(
                                                color: Palette.textDim,
                                                fontSize: 12.5)),
                                      ]),
                                    ),
                                ] else if (child.geofences.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(l.t('child_no_zones'),
                                      style: const TextStyle(
                                          color: Palette.textDim,
                                          fontSize: 12.5)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ---- Alerts (links to the feed, which owns filtering) ----
                          DsCard(
                            onTap: () =>
                                Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  AlertsScreen(controller: controller),
                            )),
                            child: Row(children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Ds.ink,
                                      width: DsShape.borderWidth),
                                  color: Palette.violet.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                    Icons.notifications_none_rounded,
                                    size: 20,
                                    color: Palette.violet),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(l.t('child_alerts'),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Text('${mine.length}',
                                  style: const TextStyle(
                                      fontFamily: 'JetBrainsMono',
                                      fontWeight: FontWeight.w700,
                                      color: Palette.violet)),
                              const Icon(Icons.chevron_right_rounded,
                                  size: 20, color: Palette.textDim),
                            ]),
                          ),

                          // ---- Care hub ----
                          //
                          // The development calendar, vaccinations and growth
                          // chart were reachable only as three small header
                          // icons — easy to miss, and the header is where the
                          // eye goes last. As cards with a one-line summary they
                          // are discoverable, and each says why it is worth
                          // opening. Only with a date of birth, which all three
                          // are keyed on.
                          if (child.hasDateOfBirth) ...[
                            const SizedBox(height: 22),
                            Text(l.t('child_care').toUpperCase(),
                                style: const TextStyle(
                                    color: Palette.textDim,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6)),
                            const SizedBox(height: 10),
                            // Only for a baby, not a toddler: a feed-and-nappy
                            // log stops making sense once they are eating at the
                            // table. Six months is a generous edge.
                            if (child.ageInMonths(now) < 6) ...[
                              _CareCard(
                                icon: Icons.child_friendly_outlined,
                                title: l.t('nb_title'),
                                summary: _newbornSummary(
                                    l, controller.newbornLogFor(child.id), now),
                                onTap: () => openNewbornLog(
                                    context, controller, child, now),
                              ),
                              const SizedBox(height: 12),
                            ],
                            // Cry analysis — a discoverable card, not a header icon
                            // buried in the newborn log. Needs sign-in (the
                            // classifier is reached through the authenticated
                            // backend proxy).
                            if (child.ageInMonths(now) < 6 &&
                                controller.isSignedIn) ...[
                              _CareCard(
                                icon: Icons.graphic_eq_rounded,
                                title: l.t('cry_title'),
                                summary: _crySummary(l, controller.cryHistory),
                                onTap: () =>
                                    openCryInsight(context, controller),
                              ),
                              const SizedBox(height: 12),
                            ],
                            _CareCard(
                              icon: Icons.timeline_rounded,
                              title: l.t('dev_title'),
                              summary: _developmentSummary(
                                  l, child.ageInMonths(now)),
                              onTap: () =>
                                  openDevelopment(context, child, now),
                            ),
                            const SizedBox(height: 12),
                            _CareCard(
                              icon: Icons.vaccines_outlined,
                              title: l.t('vac_title'),
                              summary: _vaccinationSummary(
                                  l,
                                  child.ageInMonths(now),
                                  controller.vaccinesDoneFor(child.id)),
                              onTap: () => openVaccinations(
                                  context, controller, child, now),
                            ),
                            const SizedBox(height: 12),
                            _CareCard(
                              icon: Icons.monitor_weight_outlined,
                              title: l.t('grw_title'),
                              summary: _growthSummary(
                                  l, controller.growthFor(child.id)),
                              onTap: () =>
                                  openGrowth(context, controller, child),
                            ),
                            // Weaning: shown across the window when solids matter
                            // (about four months to just past the first birthday).
                            if (isSolidsWindow(child.ageInMonths(now))) ...[
                              const SizedBox(height: 12),
                              _CareCard(
                                icon: Icons.restaurant_outlined,
                                title: l.t('sol_card_title'),
                                summary:
                                    _solidsSummary(l, child.ageInMonths(now)),
                                onTap: () => openSolids(context, child, now),
                              ),
                            ],
                            // Home safety: relevant from birth and growing with
                            // the child. Persisted household-wide.
                            const SizedBox(height: 12),
                            _CareCard(
                              icon: Icons.shield_outlined,
                              title: l.t('hs_card_title'),
                              summary: _homeSafetySummary(
                                  l,
                                  controller.homeSafetyDone,
                                  child.ageInMonths(now)),
                              onTap: () => openHomeSafety(
                                  context, controller, child, now),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// One rule, in one place. This used to be its own switch with `danger` on
  /// critical, and the map screen had a second copy of the same table — which
  /// is how one of them stays red after the other is fixed.
  static Color _batteryColor(int pct) => batteryColor(pct);
}

/// A one-line summary for the development card: what is happening now, or the
/// soonest thing ahead.
String _developmentSummary(L10n l, int ageMonths) {
  final now = milestonesNow(ageMonths);
  if (now.isNotEmpty) return l.t('dev_${now.first.id}');
  final next = milestonesAhead(ageMonths, limit: 1);
  return next.isEmpty ? l.t('dev_sub') : l.t('dev_${next.first.id}');
}

/// The vaccination card: anything to catch up on, else due now, else the next
/// visit. Catch-up (past its age and not recorded done) outranks the rest —
/// it's the one thing that might need action.
String _vaccinationSummary(L10n l, int ageMonths, Set<String> done) {
  if (vaccinesToCatchUp(ageMonths, done).isNotEmpty) return l.t('vac_catchup');
  if (vaccinesDue(ageMonths).isNotEmpty) return l.t('vac_due');
  final months = monthsUntilNextVisit(ageMonths);
  return months == null
      ? l.t('vac_complete')
      : l.t('vac_in_months', {'n': months});
}

/// The growth card: the latest weight, or an invitation to record one.
String _growthSummary(L10n l, List<GrowthPoint> points) {
  final w = weightSeries(points);
  if (w.isEmpty) return l.t('grw_add');
  return '${w.last.weightKg!.toStringAsFixed(1)} ${l.t('grw_kg')}';
}

/// A tappable care-hub card: icon, title, and a one-line summary of why to open
/// it.
class _CareCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;
  const _CareCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => DsCard(
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: Palette.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: Palette.violet),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: Palette.textDim),
        ]),
      );
}

/// The newborn card summary: today's feed and diaper counts, or an invitation.
String _homeSafetySummary(L10n l, Set<String> done, int ageMonths) {
  final count = homeSafetyDoneCount(done, ageMonths);
  final total = homeSafetyRelevantTotal(ageMonths);
  return count == total && total > 0
      ? l.t('hs_all_done')
      : l.t('hs_progress', {'n': count, 'total': total});
}

String _solidsSummary(L10n l, int ageMonths) {
  final until = monthsUntilSolids(ageMonths);
  // Before the start age it counts down; once weaning is underway it names the
  // card's job rather than a number.
  return until != null ? l.t('sol_until', {'n': until}) : l.t('sol_card_sub');
}

String _newbornSummary(L10n l, List<NewbornEvent> events, DateTime today) {
  final s = summaryFor(events, today);
  if (s.isEmpty) return l.t('nb_empty');
  final counts =
      '${l.t('nb_feeds')} ${s.feeds} · ${l.t('nb_diapers')} ${s.diapers}';
  // Lead with the 3am question — "when was the last feed" — so a parent can
  // answer it from the card without opening the log. Only when a feed exists.
  final lastFeed = lastOfKind(events, NewbornEventKind.feed);
  if (lastFeed == null) return counts;
  final ago =
      l.t('nb_last', {'ago': l.ago(today.difference(lastFeed.at).abs())});
  return '$ago · $counts';
}

/// Card summary for the cry-analysis tool: the last reason if there's history,
/// else the one-line intro.
String _crySummary(L10n l, List<CryResult> history) {
  if (history.isEmpty) return l.t('cry_intro');
  final code = CryReason.fromCode(history.first.reason) == null
      ? 'unknown'
      : history.first.reason;
  return l.t('cry_last', {'reason': l.t('cry_reason_$code')});
}

class _Header extends StatelessWidget {
  final ChildProfile child;
  final DateTime now;
  final AppController controller;
  const _Header(
      {required this.child, required this.now, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Row(
      children: [
        PhotoAvatar(
          photoPath: child.photoPath,
          name: child.name,
          size: 64,
          fallbackIcon: child.gender == Gender.boy
              ? Icons.boy
              : child.gender == Gender.girl
                  ? Icons.girl
                  : Icons.child_care,
        ),
        const SizedBox(width: 16),
        // The name lives in the (pinned) app bar, so it isn't repeated here.
        Expanded(
          child: Text(
            child.hasDateOfBirth
                ? l.childAge(child.ageInMonths(now))
                : l.t('child_no_dob'),
            style: TextStyle(
              fontSize: child.hasDateOfBirth ? 16 : 13.5,
              fontWeight:
                  child.hasDateOfBirth ? FontWeight.w600 : FontWeight.w400,
              color: child.hasDateOfBirth ? Palette.text : Palette.textDim,
            ),
          ),
        ),
        // The age is exactly where a parent wonders what comes next, so the
        // development calendar hangs off it. Shown only with a date of birth:
        // without one the calendar has nothing to place her child on.
        // The development / vaccination / growth entry points live in the care
        // hub in the body now, not here — two ways to the same screen is the
        // duplicate-control smell, and the cards carry a summary the icon
        // never could.
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _StatusRow(
      {required this.icon,
      required this.color,
      required this.label,
      required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 13.5)),
        ]),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 14, color: Palette.border);
}
